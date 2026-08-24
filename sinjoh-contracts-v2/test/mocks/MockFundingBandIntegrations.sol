// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FundingBandObservation } from "../../src/bands/FundingBandTypes.sol";
import { IFundingBandMarketCapGuard } from "../../src/interfaces/IFundingBandMarketCapGuard.sol";
import { IFundingBandPositionAdapter } from "../../src/interfaces/IFundingBandPositionAdapter.sol";

contract MockFundingBandPool { }

contract MockFundingBandGuard is IFundingBandMarketCapGuard {
    address public override bandsContract;
    address public immutable override subject;
    address public immutable override quoteAsset;
    address public immutable override canonicalPool;
    address public immutable override factory;
    address public immutable override quoteUsdOracle;
    uint256 public constant override tickReferenceQuoteUsdE8 = 1e8;
    uint256 public immutable override referenceSupply;
    uint32 public constant override minimumTwapWindow = 15 minutes;
    FundingBandObservation private _observation;

    constructor(address subject_, address quote_, address pool_, uint256 supply_) {
        subject = subject_;
        quoteAsset = quote_;
        canonicalPool = pool_;
        factory = pool_;
        quoteUsdOracle = pool_;
        referenceSupply = supply_;
    }

    function bind(address bands) external {
        require(bandsContract == address(0), "bound");
        bandsContract = bands;
    }

    function setObservation(
        uint256 marketCapUsdE8,
        uint48 observedAt,
        bytes32 observationId,
        int24 lowerTick,
        int24 upperTick
    ) external {
        _observation = FundingBandObservation({
            marketCapUsdE8: marketCapUsdE8,
            observedAt: observedAt,
            observationId: observationId,
            effectiveLowerTick: lowerTick,
            effectiveUpperTick: upperTick
        });
    }

    function observe(uint128, uint128, bytes calldata)
        external
        view
        returns (FundingBandObservation memory observation)
    {
        return _observation;
    }
}

    contract MockFundingBandPositionAdapter is ERC721, IFundingBandPositionAdapter {
        using SafeERC20 for IERC20;
        using SafeCast for uint256;

        address public override bandsContract;
        address public immutable override subject;
        address public immutable override quoteAsset;
        address public immutable override canonicalPool;
        address public immutable override factory;
        address public immutable override positionManager;
        uint256 public nextPositionId = 1;
        uint256 public openResidual;
        uint256 public settlementSubject;
        uint256 public settlementQuote;
        mapping(uint256 positionId => uint128 liquidity) private _liquidity;

        constructor(address subject_, address quote_, address pool_)
            ERC721("Band Position", "BAND-POS")
        {
            subject = subject_;
            quoteAsset = quote_;
            canonicalPool = pool_;
            factory = pool_;
            positionManager = address(this);
        }

        function bind(address bands) external {
            require(bandsContract == address(0), "bound");
            bandsContract = bands;
        }

        function configureOpenResidual(uint256 residual) external {
            openResidual = residual;
        }

        function configureSettlement(uint256 subjectAmount, uint256 quoteAmount) external {
            settlementSubject = subjectAmount;
            settlementQuote = quoteAmount;
        }

        function open(uint256, uint256 subjectAmount, int24, int24)
            external
            returns (uint256 positionId, uint128 liquidity, uint256 subjectResidual)
        {
            require(msg.sender == bandsContract, "bands");
            subjectResidual = openResidual;
            uint256 spent = subjectAmount - subjectResidual;
            IERC20(subject).safeTransferFrom(msg.sender, address(this), spent);
            liquidity = spent.toUint128();
            positionId = nextPositionId++;
            _liquidity[positionId] = liquidity;
            _safeMint(msg.sender, positionId);
        }

        function increase(uint256 positionId, uint256 subjectAmount)
            external
            returns (uint128 liquidityAdded, uint256 subjectResidual)
        {
            require(msg.sender == bandsContract && _ownerOf(positionId) == bandsContract, "bands");
            subjectResidual = openResidual;
            uint256 spent = subjectAmount - subjectResidual;
            IERC20(subject).safeTransferFrom(msg.sender, address(this), spent);
            liquidityAdded = spent.toUint128();
            _liquidity[positionId] += liquidityAdded;
        }

        function exitAll(uint256 positionId, address recipient, bool)
            external
            returns (address[] memory assets, uint256[] memory amounts)
        {
            require(msg.sender == bandsContract && recipient == bandsContract, "bands");
            require(getApproved(positionId) == address(this), "approval");
            _liquidity[positionId] = 0;
            _burn(positionId);
            uint256 subjectBalance = IERC20(subject).balanceOf(address(this));
            if (subjectBalance > settlementSubject) {
                IERC20(subject).safeTransfer(address(0xdead), subjectBalance - settlementSubject);
            }
            if (settlementSubject != 0) IERC20(subject).safeTransfer(recipient, settlementSubject);
            if (settlementQuote != 0) IERC20(quoteAsset).safeTransfer(recipient, settlementQuote);
            bool subjectFirst = subject < quoteAsset;
            assets = new address[](2);
            amounts = new uint256[](2);
            assets[0] = subjectFirst ? subject : quoteAsset;
            assets[1] = subjectFirst ? quoteAsset : subject;
            amounts[0] = subjectFirst ? settlementSubject : settlementQuote;
            amounts[1] = subjectFirst ? settlementQuote : settlementSubject;
        }

        function positionLiquidity(uint256 positionId) external view returns (uint128 liquidity) {
            return _liquidity[positionId];
        }
    }
