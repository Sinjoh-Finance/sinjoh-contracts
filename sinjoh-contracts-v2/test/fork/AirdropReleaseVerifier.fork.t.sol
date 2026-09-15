// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {AirdropCompositeLifecycleForkTest} from "./AirdropCompositeLifecycle.fork.t.sol";
import {AirdropReleaseVerifier} from "../../src/yield-banks/airdrop/AirdropReleaseVerifier.sol";
import {StockReleaseVerifier} from "../../src/yield-banks/stock/StockReleaseVerifier.sol";
import {DeltaPoolController} from "../../src/yield-banks/DeltaPoolController.sol";
import {DeltaV3TwapUsdFeed} from "../../src/yield-banks/adapters/DeltaV3TwapUsdFeed.sol";
import {IYieldBankV3Pool} from "../../src/yield-banks/interfaces/IYieldBankV3.sol";
import {AirdropAssetRegistry} from "../../src/yield-banks/airdrop/AirdropAssetRegistry.sol";
import {AirdropObservationPublisher} from "../../src/yield-banks/airdrop/AirdropObservationPublisher.sol";

import {AirdropQuoteReader} from "../../src/yield-banks/airdrop/AirdropQuoteReader.sol";
import {StockDividendRoute} from "../../src/yield-banks/stock/StockDividendRoute.sol";

contract AirdropReleaseVerifierForkTest is AirdropCompositeLifecycleForkTest {
    function testFinalVerifierChecksRealThreeTokenReleaseAndRejectsIncompleteOrDriftedConfiguration() public {
        airCount=3;_fork();
        DeltaPoolController controller=DeltaPoolController(address(ALLOCATOR.deltaPoolController()));
        bytes32 original=_infrastructureHash(address(controller),OLD_FACTORY);
        _deployInfrastructure();_registerComposite(controller);_configure(controller);
        address governance=COLLECTION.collectionTimelock();
        (address stockExit,)=composite.stockExitRoute(NVDA);
        address cashRoute=_route(USDG_POOL,WETH,USDG);
        address dividends=address(new StockDividendRoute(stockExit,cashRoute));
        vm.prank(governance);stockVault.setDividendRoute(NVDA,dividends);
        address wethFeed=hub.feedDetails(WETH).feed;
        DeltaV3TwapUsdFeed direct=new DeltaV3TwapUsdFeed(INJOH,WETH,INJOH_POOL,OLD_FACTORY,wethFeed,INJOH_POOL.codehash,OLD_FACTORY.codehash,wethFeed.codehash,1800,300,1e18,IYieldBankV3Pool(INJOH_POOL).liquidity()/2,"Airdrop V3 TWAP / USD");
        vm.prank(governance);hub.configureFeed(INJOH,address(direct),address(0),86400,0,false,false,300);
        AirdropObservationPublisher publisher=new AirdropObservationPublisher(governance,address(0xB0B),new address[](0));
        AirdropReleaseVerifier verifier=new AirdropReleaseVerifier();
        AirdropAssetRegistry registry=airVault.registry();
        address[] memory stocks=new address[](1);stocks[0]=NVDA;
        (,,,,bytes32 manifestHash)=stockVault.registry().assets(NVDA);
        AirdropReleaseVerifier.Release memory r;
        r.stock=StockReleaseVerifier.Activation(address(controller),registrationPool,address(composite),address(facade),address(stockVault),address(lpVault),address(lpAdapter),OLD_FACTORY,INJOH_POOL,original,manifestHash,stocks);
        r.sleeveHash=address(composite).codehash;r.collection=address(COLLECTION);r.vault=address(airVault);r.registry=address(registry);
        r.targetBook=address(book);r.catalogHash=registry.catalogHash();r.priceHub=address(hub);r.publisher=address(publisher);r.observer=address(0xB0B);
        r.priceReader=address(new AirdropQuoteReader(address(publisher)));r.priceReaderHash=r.priceReader.codehash;r.publisherHash=address(publisher).codehash;r.vaultHash=address(airVault).codehash;
        r.assets=new AirdropReleaseVerifier.Asset[](3);
        for(uint256 i;i<3;++i){
            address token=registry.listed(i);AirdropReleaseVerifier.Asset memory a;
            a.token=token;(a.tokenHash,a.evidenceHash,a.decimals,a.enabled)=registry.assets(token);
            a.minimumHolding=registry.minimumHoldingUnits(token);
            (a.entry,a.entryHash)=composite.airdropEntryRoute(token);(a.exit,a.exitHash)=composite.airdropExitRoute(token);
            a.feed=hub.feedDetails(token).feed;a.feedHash=a.feed.codehash;
            a.claims=new AirdropReleaseVerifier.Claim[](registry.claimRouteCount(token));
            for(uint256 j;j<a.claims.length;++j){AirdropAssetRegistry.ClaimRoute memory c=registry.claimRoute(token,j);a.claims[j]=AirdropReleaseVerifier.Claim(c.adapter,c.codeHash,c.reward);}
            r.assets[i]=a;
        }
        verifier.verifyAirdrop(r);
        r.observer=address(0xBAD);vm.expectRevert(StockReleaseVerifier.ActivationMismatch.selector);verifier.verifyAirdrop(r);r.observer=address(0xB0B);
        r.sleeveHash=bytes32(uint256(1));vm.expectRevert(StockReleaseVerifier.ActivationMismatch.selector);verifier.verifyAirdrop(r);r.sleeveHash=address(composite).codehash;
        address reward=r.assets[0].claims[0].reward;r.assets[0].claims[0].reward=address(0xBAD);vm.expectRevert(StockReleaseVerifier.ActivationMismatch.selector);verifier.verifyAirdrop(r);r.assets[0].claims[0].reward=reward;
        r.assets[1]=r.assets[0];vm.expectRevert(StockReleaseVerifier.ActivationMismatch.selector);verifier.verifyAirdrop(r);
    }
}
