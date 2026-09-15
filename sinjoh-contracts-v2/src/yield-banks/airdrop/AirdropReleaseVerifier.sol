// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {StockReleaseVerifier} from "../stock/StockReleaseVerifier.sol";
import {AirdropCompositeSleeve} from "./AirdropCompositeSleeve.sol";
import {AirdropVault} from "./AirdropVault.sol";
import {AirdropTargetBook} from "./AirdropTargetBook.sol";
import {AirdropAssetRegistry,IAirdropClaimAdapter} from "./AirdropAssetRegistry.sol";
import {AirdropObservationPublisher} from "./AirdropObservationPublisher.sol";
import {AirdropObservedV4UsdFeed} from "./AirdropObservedV4UsdFeed.sol";
import {DeltaV3TwapUsdFeed} from "../adapters/DeltaV3TwapUsdFeed.sol";
import {AirdropQuoteReader} from "./AirdropQuoteReader.sol";
import {PriceHub} from "../PriceHub.sol";

/// @notice Final atomic assertions for the complete release, including Stock/LP migration
/// dependencies. Market availability is checked again for each owner trade; temporary price
/// circuit breakers must not require a different governance operation to recover.
contract AirdropReleaseVerifier is StockReleaseVerifier {
    struct Claim {address adapter;bytes32 codeHash;address reward;}
    struct Asset {
        address token;bytes32 tokenHash;bytes32 evidenceHash;uint8 decimals;bool enabled;
        uint256 minimumHolding;address entry;bytes32 entryHash;address exit;bytes32 exitHash;
        address feed;bytes32 feedHash;bool observed;Claim[] claims;
    }
    struct Release {
        Activation stock;bytes32 sleeveHash;address collection;address vault;address registry;
        address targetBook;bytes32 catalogHash;address priceHub;address publisher;address observer;
        address priceReader;bytes32 priceReaderHash;bytes32 publisherHash;bytes32 vaultHash;
        Asset[] assets;
    }
    function verifyAirdrop(Release calldata r) external view {
        this.verify(r.stock);
        AirdropCompositeSleeve sleeve=AirdropCompositeSleeve(r.stock.sleeve);
        AirdropVault vault=AirdropVault(r.vault);
        AirdropAssetRegistry registry=AirdropAssetRegistry(r.registry);
        AirdropObservationPublisher publisher=AirdropObservationPublisher(r.publisher);
        address governance=sleeve.governance();
        if(r.stock.sleeve.codehash!=r.sleeveHash||r.sleeveHash==bytes32(0)||r.assets.length==0||r.assets.length>100
            ||address(sleeve.collection())!=r.collection||address(sleeve.airdropVault())!=r.vault
            ||address(sleeve.targetBook())!=r.targetBook||address(AirdropTargetBook(r.targetBook).sleeve())!=r.stock.sleeve
            ||vault.controller()!=r.stock.sleeve||address(vault.collection())!=r.collection
            ||address(vault.registry())!=r.registry||registry.owner()!=governance||registry.catalogHash()!=r.catalogHash
            ||sleeve.priceHub()!=r.priceHub||sleeve.maximumOperatorLossBps()!=500
            ||publisher.owner()!=governance||publisher.observer()!=r.observer||r.observer==governance
            ||r.observer==address(0)||r.priceReader.code.length==0||r.priceReader.codehash!=r.priceReaderHash
            ||r.publisher.codehash!=r.publisherHash||r.vault.codehash!=r.vaultHash
            ||address(AirdropQuoteReader(r.priceReader).publisher())!=r.publisher
            ||AirdropQuoteReader(r.priceReader).publisherCodeHash()!=r.publisherHash)revert ActivationMismatch();
        for(uint256 i;i<r.assets.length;++i){
            for(uint256 j;j<i;++j)if(r.assets[j].token==r.assets[i].token)revert ActivationMismatch();
            _asset(r.assets[i],sleeve,registry,PriceHub(r.priceHub),publisher);
        }
        // Reject an activation that silently left an extra registry asset outside its manifest.
        try registry.listed(r.assets.length) returns(address){revert ActivationMismatch();}catch{}
    }
    function _asset(Asset calldata a,AirdropCompositeSleeve sleeve,AirdropAssetRegistry registry,PriceHub hub,AirdropObservationPublisher publisher) private view {
        if(a.token.code.length==0||a.token.codehash!=a.tokenHash||a.entry.code.length==0||a.entry.codehash!=a.entryHash
            ||a.exit.code.length==0||a.exit.codehash!=a.exitHash||a.feed.code.length==0||a.feed.codehash!=a.feedHash
            ||a.minimumHolding==0||a.claims.length==0||a.claims.length>8)revert ActivationMismatch();
        (bytes32 tokenHash,bytes32 evidence,uint8 decimals,bool enabled)=registry.assets(a.token);
        if(tokenHash!=a.tokenHash||evidence!=a.evidenceHash||decimals!=a.decimals||enabled!=a.enabled
            ||registry.minimumHoldingUnits(a.token)!=a.minimumHolding||registry.claimRouteCount(a.token)!=a.claims.length)revert ActivationMismatch();
        (address entry,bytes32 entryHash)=sleeve.airdropEntryRoute(a.token);
        (address exit,bytes32 exitHash)=sleeve.airdropExitRoute(a.token);
        if(entry!=a.entry||entryHash!=a.entryHash||exit!=a.exit||exitHash!=a.exitHash)revert ActivationMismatch();
        PriceHub.FeedConfig memory config=hub.feedDetails(a.token);
        if(config.feed!=a.feed||config.feedRuntimeCodeHash!=a.feedHash||!config.supported
            ||config.corporateActionPaused||config.weekdaysOnly||config.checkAssetOraclePause||config.gracePeriod!=0
            ||config.referenceSource!=address(0)||config.heartbeat!=(a.observed?120:86400))revert ActivationMismatch();
        if(a.observed){
            AirdropObservedV4UsdFeed feed=AirdropObservedV4UsdFeed(a.feed);
            if(feed.subject()!=a.token||address(feed.priceHub())!=address(hub)||feed.quoteSigner()!=address(publisher)
                ||feed.owner()!=sleeve.governance()||feed.WINDOW()!=1800||feed.MAX_AGE()!=120
                ||feed.maxSpotDeviationBps()!=300||publisher.feedCodeHash(a.feed)!=a.feedHash)revert ActivationMismatch();
        }else{
            DeltaV3TwapUsdFeed feed=DeltaV3TwapUsdFeed(a.feed);
            if(feed.pairedAsset()!=a.token||feed.weth()!=0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73
                ||address(feed.wethUsdFeed())!=0x78F3556b67E17Df817D51Ef5a990cDaF09E8d3A9
                ||feed.twapWindow()!=1800||feed.maxSpotDeviationBps()!=300)revert ActivationMismatch();
        }
        for(uint256 i;i<a.claims.length;++i){
            Claim calldata c=a.claims[i];IAirdropClaimAdapter(c.adapter).validate();AirdropAssetRegistry.ClaimRoute memory route=registry.claimRoute(a.token,i);
            if(route.adapter!=c.adapter||route.codeHash!=c.codeHash||route.reward!=c.reward
                ||c.adapter.codehash!=c.codeHash||IAirdropClaimAdapter(c.adapter).subject()!=a.token
                ||IAirdropClaimAdapter(c.adapter).rewardAsset()!=c.reward)revert ActivationMismatch();
        }
    }
}
