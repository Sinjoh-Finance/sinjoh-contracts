// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IPonsV2FeeEscrow, IPonsV2LaunchFactory } from "../../src/interfaces/IPonsV2.sol";
import { MockERC20 } from "./MockERC20.sol";

contract MockWETH is MockERC20 {
    constructor() MockERC20("Wrapped Ether", "WETH") { }

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        totalSupply += msg.value;
        balanceOf[msg.sender] += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }
}

contract MockPonsV2Curve {
    MockPonsV2FeeEscrow public escrow;
    address public feeRecipient;
    uint256 public quoteFeeBalance;
    uint256 public creatorTaxBalance;
    uint256 public buybackQuoteBalance;

    receive() external payable { }

    function configure(MockPonsV2FeeEscrow escrow_, address feeRecipient_) external {
        escrow = escrow_;
        feeRecipient = feeRecipient_;
    }

    function accrue(uint256 fee, uint256 tax) external payable {
        require(msg.value == fee + tax, "VALUE_MISMATCH");
        quoteFeeBalance += fee;
        creatorTaxBalance += tax;
    }

    function setBuybackQuoteBalance(uint256 value) external {
        buybackQuoteBalance = value;
    }

    function sweepFees(uint256) external {
        require(msg.sender == feeRecipient, "NOT_RECIPIENT");
        uint256 pending = quoteFeeBalance + creatorTaxBalance;
        quoteFeeBalance = 0;
        creatorTaxBalance = 0;
        escrow.creditNative{ value: pending }(feeRecipient);
    }
}

contract MockPonsV2FeeEscrow is IPonsV2FeeEscrow {
    mapping(address recipient => uint256 amount) public override balanceOf;
    mapping(address recipient => mapping(address token => uint256 amount))
        public
        override balanceOfToken;

    receive() external payable { }

    function creditNative(address recipient) external payable {
        balanceOf[recipient] += msg.value;
    }

    function creditToken(address recipient, address token, uint256 amount) external {
        MockERC20(token).mint(address(this), amount);
        balanceOfToken[recipient][token] += amount;
    }

    function claim() external returns (uint256 amount) {
        amount = balanceOf[msg.sender];
        balanceOf[msg.sender] = 0;
        (bool success,) = msg.sender.call{ value: amount }("");
        require(success, "NATIVE_TRANSFER_FAILED");
    }

    function claimToken(address token) external returns (uint256 amount) {
        amount = balanceOfToken[msg.sender][token];
        balanceOfToken[msg.sender][token] = 0;
        bool transferred = MockERC20(token).transfer(msg.sender, amount);
        require(transferred, "TOKEN_TRANSFER_FAILED");
    }
}

    contract MockPonsV2LaunchFactory is IPonsV2LaunchFactory {
        address public immutable override feeEscrow;
        bool public override launchEnabled = true;
        uint256 public override launchFee;
        uint256 public override maxCreatorTaxBps = 5_000;
        bytes32 public economics = keccak256("PONS_V2_ECONOMICS");
        bool public corruptReadback;

        mapping(address launcher => bool allowed) public override whitelistedLaunchers;
        mapping(address token => LaunchedToken launched) private _launchedTokens;

        address public lastDeployer;
        address public lastToken;
        uint16 public lastCreatorTaxBps;
        address public lastCreatorFeeRecipient;

        address public override launchDeployer;
        address public override memeHook;
        address public override buybackVault;
        address public override poolManager;

        constructor(address feeEscrow_) {
            feeEscrow = feeEscrow_;
        }

        function getLaunchConfig(uint256) external pure override returns (LaunchConfig memory) {
            return LaunchConfig({
                supply: 1_000_000_000 ether,
                curveFeeBps: 100,
                phantomQuote: 1 ether,
                graduationThreshold: 4.2 ether,
                poolFee: 0,
                tickSpacing: 200,
                enabled: true
            });
        }

        function pairTokenEconomics(address)
            external
            pure
            override
            returns (uint256, uint256, uint8)
        {
            return (0, 0, 0);
        }

        function setLaunchEnabled(bool enabled) external {
            launchEnabled = enabled;
        }

        function setWhitelistedLauncher(address launcher, bool allowed) external {
            whitelistedLaunchers[launcher] = allowed;
        }

        function setLaunchFee(uint256 fee) external {
            launchFee = fee;
        }

        function setMaxCreatorTaxBps(uint256 cap) external {
            maxCreatorTaxBps = cap;
        }

        function setEconomics(bytes32 expected) external {
            economics = expected;
        }

        function setCorruptReadback(bool corrupt) external {
            corruptReadback = corrupt;
        }

        function previewLaunchEconomics(uint256, address) external view returns (bytes32) {
            return economics;
        }

        address[] public lastSnipeTaxExemptions;

        function launchToken(TokenParams calldata params, uint256 launchConfigId, address pairToken)
            external
            payable
            returns (address token, address curve)
        {
            return _launch(params, launchConfigId, pairToken);
        }

        function launchToken(
            TokenParams calldata params,
            uint256 launchConfigId,
            address pairToken,
            address[] calldata snipeTaxExemptions
        ) external payable returns (address token, address curve) {
            lastSnipeTaxExemptions = snipeTaxExemptions;
            return _launch(params, launchConfigId, pairToken);
        }

        function snipeTaxExemptionCount() external view returns (uint256) {
            return lastSnipeTaxExemptions.length;
        }

        function _launch(TokenParams calldata params, uint256, address pairToken)
            private
            returns (address token, address curve)
        {
            require(msg.value == launchFee, "WRONG_LAUNCH_FEE");
            require(params.salt != bytes32(0), "MISSING_SALT");
            require(params.expectedEconomics == economics, "ECONOMICS_CHANGED");
            require(params.creatorTaxBps <= maxCreatorTaxBps, "TAX_TOO_HIGH");

            token = address(new MockERC20(params.name, params.symbol));
            curve = address(new MockPonsV2Curve());
            lastDeployer = msg.sender;
            lastToken = token;
            lastCreatorTaxBps = params.creatorTaxBps;
            lastCreatorFeeRecipient = params.creatorFeeRecipient;
            _launchedTokens[token] = LaunchedToken({
                token: token,
                curve: curve,
                deployer: msg.sender,
                creatorFeeRecipient: params.creatorFeeRecipient,
                pairToken: pairToken,
                graduationThreshold: 1 ether,
                poolFee: 3_000,
                tickSpacing: 60,
                creatorTaxBps: params.creatorTaxBps,
                buybackEnabled: params.buybackEnabled,
                phase: 0,
                sweptQuote: 0,
                sweptTokens: 0,
                sweptAt: 0,
                exists: true
            });
        }

        function getLaunchedToken(address token)
            external
            view
            returns (LaunchedToken memory launched)
        {
            launched = _launchedTokens[token];
            if (corruptReadback) launched.creatorTaxBps += 1;
        }
    }
