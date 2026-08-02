// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IPonsV2LaunchFactory } from "../../src/interfaces/IPonsV2.sol";

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    function setDecimals(uint8 decimals_) external {
        decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockWETH is MockERC20 {
    constructor() MockERC20("Wrapped Ether", "WETH", 18) { }

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }
}

contract MockFeeEscrow {
    error NoBalance();

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public balanceOfToken;

    function credit(address recipient) external payable {
        balanceOf[recipient] += msg.value;
    }

    function creditToken(address recipient, address token, uint256 amount) external {
        balanceOfToken[recipient][token] += amount;
        MockERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    function claim() external returns (uint256 amount) {
        amount = balanceOf[msg.sender];
        if (amount == 0) revert NoBalance();
        balanceOf[msg.sender] = 0;
        (bool sent,) = payable(msg.sender).call{ value: amount }("");
        require(sent, "transfer failed");
    }

    function claimToken(address token) external returns (uint256 amount) {
        amount = balanceOfToken[msg.sender][token];
        if (amount == 0) revert NoBalance();
        balanceOfToken[msg.sender][token] = 0;
        MockERC20(token).transfer(msg.sender, amount);
    }
}

/// @dev Reproduces the curve behaviours the adapter must survive: a buy that
/// mints to `recipient`, a clamp that consumes less than `quoteIn` and refunds
/// the remainder, and the two-step fee path where trading fees accrue on the
/// curve and only reach the escrow via `sweepFees`.
contract MockBondingCurve {
    error AlreadyGraduated();
    error NotFeeSweepOperator();

    address public token;
    address public pairToken;
    address public deployer;
    address public creatorFeeRecipient;
    MockFeeEscrow public feeEscrow;

    uint256 public clampTo = type(uint256).max;
    uint256 public rate = 1000;
    uint16 public feeBps = 100;

    uint256 public quoteFeeBalance;
    uint256 public creatorTaxBalance;
    uint256 public buybackQuoteBalance;
    bool public graduated;

    constructor(
        address pairToken_,
        address deployer_,
        address creatorFeeRecipient_,
        MockFeeEscrow feeEscrow_
    ) {
        pairToken = pairToken_;
        deployer = deployer_;
        creatorFeeRecipient = creatorFeeRecipient_;
        feeEscrow = feeEscrow_;
    }

    function initialize(address token_) external {
        token = token_;
    }

    function setClamp(uint256 clampTo_) external {
        clampTo = clampTo_;
    }

    function setGraduated(bool graduated_) external {
        graduated = graduated_;
    }

    /// @dev Mirrors `_requiresTrustedOperator()`: a non-zero buyback balance
    /// takes the sweep away from the deployer.
    function setBuybackQuoteBalance(uint256 amount) external {
        buybackQuoteBalance = amount;
    }

    function buy(uint256 quoteIn, uint256 minTokensOut, address recipient)
        external
        payable
        returns (uint256 tokensOut)
    {
        uint256 spent = quoteIn > clampTo ? clampTo : quoteIn;
        uint256 fee = (spent * feeBps) / 10_000;
        tokensOut = spent * rate;
        require(tokensOut >= minTokensOut, "slippage");

        if (pairToken == address(0)) {
            require(msg.value == quoteIn, "value mismatch");
            uint256 refund = quoteIn - spent;
            if (refund != 0) {
                (bool sent,) = payable(msg.sender).call{ value: refund }("");
                require(sent, "refund failed");
            }
        } else {
            MockERC20(pairToken).transferFrom(msg.sender, address(this), spent);
        }
        quoteFeeBalance += fee;
        MockERC20(token).mint(recipient, tokensOut);
    }

    /// @dev Deployer may sweep only while no buyback balance is pending, and
    /// never once graduated. A sweep with nothing pending is a no-op, not a
    /// revert.
    function sweepFees(uint256) external {
        if (graduated) revert AlreadyGraduated();
        if (msg.sender != deployer) revert NotFeeSweepOperator();
        if (buybackQuoteBalance != 0) revert NotFeeSweepOperator();

        uint256 pending = quoteFeeBalance;
        if (pending == 0) return;
        quoteFeeBalance = 0;

        if (pairToken == address(0)) {
            feeEscrow.credit{ value: pending }(creatorFeeRecipient);
        } else {
            MockERC20(pairToken).approve(address(feeEscrow), pending);
            feeEscrow.creditToken(creatorFeeRecipient, pairToken, pending);
        }
    }

    receive() external payable { }
}

contract MockLaunchFactory {
    error PairTokenNotApproved();

    address public feeEscrow;
    uint256 public launchFee = 0.0005 ether;
    bool public launchEnabled = true;
    uint256 public maxCreatorTaxBps = 1000;

    mapping(address => bool) public approvedPairTokens;
    mapping(address => uint256) private _phantomQuote;
    mapping(address => uint256) private _graduationThreshold;
    mapping(address => uint8) private _decimals;

    address public lastToken;
    address public lastCurve;
    /// @dev Applied to the next curve this factory creates, so a clamped buy
    /// can be arranged before the curve exists.
    uint256 public nextClamp = type(uint256).max;

    constructor(address feeEscrow_) {
        feeEscrow = feeEscrow_;
    }

    function setLaunchEnabled(bool enabled) external {
        launchEnabled = enabled;
    }

    function setNextClamp(uint256 clampTo) external {
        nextClamp = clampTo;
    }

    function approvePair(address pairToken, uint8 decimals_) external {
        approvedPairTokens[pairToken] = true;
        _decimals[pairToken] = decimals_;
        _phantomQuote[pairToken] = 9.68e18;
        _graduationThreshold[pairToken] = 24.2e18;
    }

    function pairTokenEconomics(address pairToken) external view returns (uint256, uint256, uint8) {
        return (_phantomQuote[pairToken], _graduationThreshold[pairToken], _decimals[pairToken]);
    }

    function previewLaunchEconomics(uint256 launchConfigId, address pairToken)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode("economics", launchConfigId, pairToken));
    }

    function launchToken(
        IPonsV2LaunchFactory.TokenParams calldata params,
        uint256 launchConfigId,
        address pairToken
    ) external payable returns (address token, address curve) {
        require(msg.value == launchFee, "LaunchFeeNotPaid");
        require(launchEnabled, "LaunchDisabled");
        if (pairToken != address(0) && !approvedPairTokens[pairToken]) {
            revert PairTokenNotApproved();
        }
        require(
            params.expectedEconomics == bytes32(0)
                || params.expectedEconomics == previewLaunchEconomics(launchConfigId, pairToken),
            "LaunchEconomicsMismatch"
        );

        MockERC20 launched = new MockERC20(params.name, params.symbol, 18);
        // `deployer` is the caller of launchToken — the adapter — which is what
        // gives it the right to sweep its own curve.
        MockBondingCurve deployed = new MockBondingCurve(
            pairToken, msg.sender, params.creatorFeeRecipient, MockFeeEscrow(feeEscrow)
        );
        deployed.initialize(address(launched));
        deployed.setClamp(nextClamp);

        lastToken = address(launched);
        lastCurve = address(deployed);
        return (address(launched), address(deployed));
    }
}

/// @dev Stands in for `SinjohFeeRouter`: records the bind and exposes the
/// adapter it was configured with.
contract MockRouter {
    error NotAuthorizedBinder();

    address public launchpadAdapter;
    address public subject;
    bool public bound;

    function setLaunchpadAdapter(address adapter) external {
        launchpadAdapter = adapter;
    }

    function bind(address subject_) external {
        if (msg.sender != launchpadAdapter) revert NotAuthorizedBinder();
        subject = subject_;
        bound = true;
    }

    receive() external payable { }
}
