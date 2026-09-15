// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {VmSafe} from "forge-std/Vm.sol";
import {AirdropQuoteReader} from "../src/yield-banks/airdrop/AirdropQuoteReader.sol";
import {PreparePiggyBanksAirdropBase} from "./PreparePiggyBanksAirdropBase.s.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {DeltaPoolController} from "../src/yield-banks/DeltaPoolController.sol";
import {AirdropRegistryDeployer} from "../src/yield-banks/airdrop/AirdropRegistryDeployer.sol";
import {AirdropPinnedReleaseCheck} from "../src/yield-banks/airdrop/AirdropPinnedReleaseCheck.sol";
import {AirdropCompositeSleeve} from "../src/yield-banks/airdrop/AirdropCompositeSleeve.sol";
import {AirdropAssetRegistry} from "../src/yield-banks/airdrop/AirdropAssetRegistry.sol";
import {AirdropCustodyFactory} from "../src/yield-banks/airdrop/AirdropCustodyFactory.sol";
import {AirdropReleaseVerifier} from "../src/yield-banks/airdrop/AirdropReleaseVerifier.sol";
import {StockReleaseVerifier} from "../src/yield-banks/stock/StockReleaseVerifier.sol";
import {AirdropObservedV4UsdFeed} from "../src/yield-banks/airdrop/AirdropObservedV4UsdFeed.sol";
import {AirdropObservationPublisher} from "../src/yield-banks/airdrop/AirdropObservationPublisher.sol";
import {DeltaV3TwapUsdFeed} from "../src/yield-banks/adapters/DeltaV3TwapUsdFeed.sol";
import {IYieldBankV3Pool} from "../src/yield-banks/interfaces/IYieldBankV3.sol";
import {PonsLifecycleAllocationRoute} from "../src/yield-banks/airdrop/PonsLifecycleAllocationRoute.sol";
import {V4SinglePoolAllocationRoute} from "../src/yield-banks/airdrop/V4SinglePoolAllocationRoute.sol";
import {AirdropChainedRoute} from "../src/yield-banks/airdrop/AirdropChainedRoute.sol";
import {PonsAirdropClaimAdapter} from "../src/yield-banks/airdrop/PonsAirdropClaimAdapter.sol";
import {SinjohAirdropClaimAdapter} from "../src/yield-banks/airdrop/SinjohAirdropClaimAdapter.sol";
import {ReflectionAirdropClaimAdapter} from "../src/yield-banks/airdrop/ReflectionAirdropClaimAdapter.sol";
interface IAirPrepareTimelock {
 function isOperationDone(bytes32) external view returns(bool);
 function isOperationPending(bytes32) external view returns(bool);
}

/// @dev Preparation only. The signed release runner must pin the reviewed input hashes,
/// linked execution-library runtime, sender nonce, output plan and total fee budget before
/// broadcasting. No owner allocations are signed here. No observation is fabricated.
contract PreparePiggyBanksAirdrop is PreparePiggyBanksAirdropBase {
 bytes32 constant STOCK_OPERATION=0xdf428b6330c22c6029ed837808480ee237fc3c797202a015d03c09f1aef28bf3;
 address constant PONS=0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
 address constant V4_MANAGER=0x8366a39CC670B4001A1121B8F6A443A643e40951;
 address constant ETH_FEED=0x78F3556b67E17Df817D51Ef5a990cDaF09E8d3A9;
 AirdropAssetRegistry airRegistry;
 AirdropCustodyFactory custodyFactory;
 AirdropObservationPublisher publisher;
 AirdropQuoteReader priceReader;
 address observer;
 address airVault;
 address targetBook;
 bytes32 catalogHash;
 bytes32 custodySalt;
 string admission;
 string claimEvidence;
 AirdropReleaseVerifier.Asset[] airAssets;
 mapping(bytes32=>address) bridgeRoutes;
 mapping(address=>bool) configuredQuotes;

 function _predecessor() internal pure override returns(bytes32){return STOCK_OPERATION;}
 function _beforePreparation() internal override {
  require(vm.isContext(VmSafe.ForgeContext.ScriptDryRun)||vm.parseJsonBool(vm.readFile("deployments/airdrop-research/release-policy.json"),".allowAuxiliaryCustodyDeployment"),"deployment disabled until revised release verification passes");
  require(block.chainid==4663,"wrong chain");
  // The isolated deployment account is funded only after this dry-run passes.
  // This affects local simulation only and is unreachable in broadcast context.
  if(vm.isContext(VmSafe.ForgeContext.ScriptDryRun)&&DEPLOYER.balance<0.01 ether)vm.deal(DEPLOYER,0.01 ether);
  observer=vm.envAddress("AIRDROP_OBSERVER_ADDRESS");
  require(observer!=address(0)&&observer!=DEPLOYER&&observer!=COLLECTION.collectionTimelock(),"dedicated observer required");
  admission=vm.readFile("deployments/airdrop-research/preparation-admission.json");
  claimEvidence=vm.readFile("deployments/airdrop-research/preparation-claims.json");
  catalogHash=keccak256(bytes(vm.readFile("deployments/airdrop-research/catalog.json")));
  require(vm.parseJsonUint(admission,".rowCount")==58,"catalog route count");
  IAirPrepareTimelock timelock=IAirPrepareTimelock(COLLECTION.collectionTimelock());
  if(!timelock.isOperationDone(STOCK_OPERATION)){
   require(timelock.isOperationPending(STOCK_OPERATION),"Stock predecessor unavailable");
   string memory stock=vm.readFile("deployments/piggy-banks-stock-preparation.json");
   address[] memory stockTargets=vm.parseJsonAddressArray(stock,".targets");
   bytes[] memory stockCalls=abi.decode(vm.parseJson(stock,".payloads"),(bytes[]));
   bytes32 salt=vm.parseJsonBytes32(stock,".salt");
   require(keccak256(abi.encode(stockTargets,new uint256[](stockTargets.length),stockCalls,bytes32(0),salt))==STOCK_OPERATION,"Stock predecessor calldata changed");
   // Local state rehearsal only, outside broadcast scope. Actual activation is ordered
   // by the existing timelock predecessor, without any privileged bypass transaction.
   for(uint256 i;i<stockTargets.length;++i){vm.prank(address(timelock));(bool ok,bytes memory reason)=stockTargets[i].call(stockCalls[i]);if(!ok)assembly("memory-safe"){revert(add(reason,32),mload(reason))}}
  }
 }
 function _deployAirdrop() internal override returns(address){
  custodyFactory=new AirdropCustodyFactory(governance);
  custodySalt=keccak256(abi.encode(catalogHash,composite,factory));
  for(uint256 i;i<58;++i){
   string memory p=string.concat(".rows[",vm.toString(i),"]");
   address token=vm.parseJsonAddress(admission,string.concat(p,".subject"));
   require(token==vm.parseJsonAddress(claimEvidence,string.concat(p,".subject")),"route and claim subjects differ");
   uint256 bindingCount=vm.parseJsonUint(claimEvidence,string.concat(p,".bindingCount"));
   for(uint256 j;j<bindingCount;++j){string memory b=string.concat(p,".bindings[",vm.toString(j),"]");address dependency=vm.parseJsonAddress(claimEvidence,string.concat(b,".address"));require(dependency.codehash==vm.parseJsonBytes32(claimEvidence,string.concat(b,".runtimeCodeHash")),"claim dependency changed");}
   AirdropReleaseVerifier.Asset memory a;
   a.token=token;a.tokenHash=token.codehash;a.evidenceHash=keccak256(abi.encode(keccak256(bytes(claimEvidence)),keccak256(bytes(admission)),token));a.decimals=IERC20Metadata(token).decimals();
   a.enabled=keccak256(bytes(vm.parseJsonString(admission,string.concat(p,".symbol"))))!=keccak256("IRA");
   a.minimumHolding=vm.parseUint(vm.parseJsonString(claimEvidence,string.concat(p,".minimumHoldingUnits")));
   (a.entry,a.exit)=_assetRoutes(p,token);a.entryHash=a.entry.codehash;a.exitHash=a.exit.codehash;
   uint256 n=vm.parseJsonUint(claimEvidence,string.concat(p,".programCount"));
   a.claims=new AirdropReleaseVerifier.Claim[](n);
   for(uint256 j;j<n;++j){string memory c=string.concat(p,".programs[",vm.toString(j),"]");address distributor=vm.parseJsonAddress(claimEvidence,string.concat(c,".distributor"));bytes32 kind=keccak256(bytes(vm.parseJsonString(claimEvidence,string.concat(c,".kind"))));address adapter;
    if(kind==keccak256("pons"))adapter=address(new PonsAirdropClaimAdapter(distributor,vm.parseJsonAddress(claimEvidence,string.concat(c,".beacon"))));
    else if(kind==keccak256("reflection"))adapter=address(new ReflectionAirdropClaimAdapter(distributor));
    else {require(kind==keccak256("sinjoh"),"unknown claim program");adapter=address(new SinjohAirdropClaimAdapter(distributor,vm.parseJsonAddress(claimEvidence,string.concat(c,".funder")),token,vm.parseJsonAddress(claimEvidence,string.concat(c,".reward"))));}
    a.claims[j]=AirdropReleaseVerifier.Claim(adapter,adapter.codehash,vm.parseJsonAddress(claimEvidence,string.concat(c,".reward")));
   }
   airAssets.push(a);
  }
  AirdropRegistryDeployer.Asset[] memory initialAssets=new AirdropRegistryDeployer.Asset[](58);
  for(uint256 i;i<58;++i){AirdropReleaseVerifier.Asset memory a=airAssets[i];address[] memory claims=new address[](a.claims.length);for(uint256 j;j<claims.length;++j)claims[j]=a.claims[j].adapter;initialAssets[i]=AirdropRegistryDeployer.Asset(a.token,a.evidenceHash,a.minimumHolding,a.enabled,claims);}
  airRegistry=(new AirdropRegistryDeployer(governance,catalogHash,initialAssets)).registry();
  (airVault,targetBook)=custodyFactory.predict(composite,address(COLLECTION),address(airRegistry),custodySalt);
  // Four V3 feeds, then exactly54 observed feeds, then their precomputed publisher.
  for(uint256 i;i<4;++i){string memory p=string.concat(".rows[",vm.toString(i),"]");require(keccak256(bytes(vm.parseJsonString(admission,string.concat(p,".kind"))))==keccak256("v3"),"V3 cohort changed");address venue=vm.parseJsonAddress(admission,string.concat(p,".pool"));address token=airAssets[i].token;
   airAssets[i].feed=address(new DeltaV3TwapUsdFeed(token,WETH,venue,OLD_FACTORY,ETH_FEED,venue.codehash,OLD_FACTORY.codehash,ETH_FEED.codehash,1800,300,uint128(10**airAssets[i].decimals),IYieldBankV3Pool(venue).liquidity()/2,"Sinjoh Airdrop V3 TWAP / USD"));airAssets[i].feedHash=airAssets[i].feed.codehash;
  }
  address predictedPublisher=vm.computeCreateAddress(DEPLOYER,vm.getNonce(DEPLOYER)+54);
  address[] memory observedFeeds=new address[](54);
  for(uint256 i=4;i<58;++i){string memory p=string.concat(".rows[",vm.toString(i),"]");
   address feed=address(new AirdropObservedV4UsdFeed(governance,predictedPublisher,vm.parseJsonAddress(admission,string.concat(p,".stateView")),address(hub),airAssets[i].token,vm.parseJsonAddress(admission,string.concat(p,".quoteAsset")),_key(p),uint128(vm.parseUint(vm.parseJsonString(admission,string.concat(p,".observation.minimumLiquidity")))),300));
   airAssets[i].feed=feed;airAssets[i].feedHash=feed.codehash;airAssets[i].observed=true;observedFeeds[i-4]=feed;
  }
  publisher=new AirdropObservationPublisher(governance,observer,observedFeeds);require(address(publisher)==predictedPublisher,"publisher nonce prediction changed");
  priceReader=new AirdropQuoteReader(address(publisher));
  return address(new AirdropReleaseVerifier());
 }
 function _assetRoutes(string memory p,address token) private returns(address entry,address exit){
  bytes32 kind=keccak256(bytes(vm.parseJsonString(admission,string.concat(p,".kind"))));
  address venue=vm.parseJsonAddress(admission,string.concat(p,".pool"));
  if(kind==keccak256("v3"))return(_bridge(venue,WETH,token),_bridge(venue,token,WETH));
  if(kind==keccak256("rewards")){entry=address(new V4SinglePoolAllocationRoute(V4_MANAGER,WETH,token,true,_key(p)));exit=address(new V4SinglePoolAllocationRoute(V4_MANAGER,WETH,token,false,_key(p)));}
  else{entry=address(new PonsLifecycleAllocationRoute(PONS,WETH,token,true));exit=address(new PonsLifecycleAllocationRoute(PONS,WETH,token,false));}
  address quote=vm.parseJsonAddress(admission,string.concat(p,".quote"));
  if(quote==address(0))return(entry,exit);
  address bridge=vm.parseJsonAddress(admission,string.concat(p,".bridge"));
  address[] memory buys=new address[](bridge==address(0)?2:3);address[] memory sells=new address[](buys.length);
  if(bridge==address(0)){buys[0]=_bridge(venue,WETH,quote);buys[1]=entry;sells[0]=exit;sells[1]=_bridge(venue,quote,WETH);}
  else{buys[0]=_bridge(USDG_POOL,WETH,bridge);buys[1]=_bridge(venue,bridge,quote);buys[2]=entry;sells[0]=exit;sells[1]=_bridge(venue,quote,bridge);sells[2]=_bridge(USDG_POOL,bridge,WETH);}
  return(address(new AirdropChainedRoute(buys)),address(new AirdropChainedRoute(sells)));
 }
 function _bridge(address venue,address input,address output) private returns(address route){bytes32 key=keccak256(abi.encode(venue,input,output));route=bridgeRoutes[key];if(route==address(0)){route=_route(venue,input,output);bridgeRoutes[key]=route;}}
 function _key(string memory p) private view returns(PoolKey memory){return PoolKey(Currency.wrap(vm.parseJsonAddress(admission,string.concat(p,".key.currency0"))),Currency.wrap(vm.parseJsonAddress(admission,string.concat(p,".key.currency1"))),uint24(vm.parseJsonUint(admission,string.concat(p,".key.fee"))),int24(vm.parseJsonInt(admission,string.concat(p,".key.tickSpacing"))),IHooks(vm.parseJsonAddress(admission,string.concat(p,".key.hooks"))));}
 function _airdropActivation() internal override {
  _call(address(custodyFactory),abi.encodeCall(AirdropCustodyFactory.deploy,(composite,address(COLLECTION),address(airRegistry),custodySalt)));
  _call(composite,abi.encodeCall(AirdropCompositeSleeve.configureAirdropVault,(airVault)));
  _call(composite,abi.encodeCall(AirdropCompositeSleeve.configureTargetBook,(targetBook)));
  for(uint256 i;i<58;++i){AirdropReleaseVerifier.Asset memory a=airAssets[i];string memory p=string.concat(".rows[",vm.toString(i),"]");
   if(a.observed){address quote=vm.parseJsonAddress(admission,string.concat(p,".quoteAsset"));if(quote!=WETH&&!configuredQuotes[quote]){configuredQuotes[quote]=true;_feed(quote,vm.parseJsonAddress(admission,string.concat(p,".quoteFeed")),86400,true);}}
   _feed(a.token,a.feed,a.observed?120:86400,false);
   if(!a.enabled)_call(address(airRegistry),abi.encodeCall(AirdropAssetRegistry.setEnabled,(a.token,true)));
   _call(composite,abi.encodeCall(AirdropCompositeSleeve.bindAirdropRoutes,(a.token,a.entry,a.exit)));
   if(!a.enabled)_call(address(airRegistry),abi.encodeCall(AirdropAssetRegistry.setEnabled,(a.token,false)));
  }
  _call(address(controller),abi.encodeCall(DeltaPoolController.setPoolDepositsPaused,(pool,false)));
  // Runtime is read only after materialization during rehearsal, so the final verifier
  // calldata is appended after other calls have run locally (see _writeAirdropPlan).
 }
 function _feed(address token,address feed,uint32 heartbeat,bool stock) private {_call(address(hub),abi.encodeWithSignature("configureFeed(address,address,address,uint32,uint32,bool,bool,uint16)",token,feed,address(0),heartbeat,uint32(0),stock,stock,uint16(stock?100:300)));}
 function _writeAirdropPlan() internal override {
  AirdropReleaseVerifier.Release memory r;
  r.stock=StockReleaseVerifier.Activation(address(controller),pool,composite,facade,vault,lpVault,lpAdapter,OLD_FACTORY,INJOH_POOL,originalInfrastructureHash,manifestHash,stocks);
  r.sleeveHash=composite.codehash;r.collection=address(COLLECTION);r.vault=airVault;r.registry=address(airRegistry);r.targetBook=targetBook;r.catalogHash=catalogHash;r.priceHub=address(hub);r.publisher=address(publisher);r.observer=observer;r.assets=airAssets;r.priceReader=address(priceReader);r.priceReaderHash=address(priceReader).codehash;r.publisherHash=address(publisher).codehash;r.vaultHash=airVault.codehash;
  AirdropReleaseVerifier(verifier).verifyAirdrop(r);
  // Included in the exact atomic batch before its schedule/execute bytes are serialized.
  vm.startBroadcast(DEPLOYER);
  AirdropPinnedReleaseCheck pinned=new AirdropPinnedReleaseCheck(verifier,abi.encode(r));
  vm.stopBroadcast();
  pinned.verify();
  _call(address(pinned),abi.encodeCall(AirdropPinnedReleaseCheck.verify,()));
  string memory k="airdropConfiguration";
  vm.serializeAddress(k,"pinnedCheck",address(pinned));vm.serializeBytes32(k,"pinnedReleaseHash",pinned.releaseHash());
  vm.serializeAddress(k,"airdropRegistry",address(airRegistry));vm.serializeAddress(k,"airdropVault",airVault);vm.serializeAddress(k,"targetBook",targetBook);vm.serializeAddress(k,"custodyFactory",address(custodyFactory));vm.serializeAddress(k,"publisher",address(publisher));vm.serializeAddress(k,"observer",observer);vm.serializeAddress(k,"priceReader",address(priceReader));vm.serializeBytes32(k,"catalogHash",catalogHash);vm.serializeBytes32(k,"predecessor",STOCK_OPERATION);
  vm.serializeBytes(k,"release",abi.encode(r));
  vm.writeJson(vm.serializeBytes(k,"finalVerifierCalldata",abi.encodeCall(AirdropReleaseVerifier.verifyAirdrop,(r))),"deployments/piggy-banks-airdrop-configuration.json");
 }
}
