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

    function withdraw(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        (bool sent,) = payable(msg.sender).call{ value: amount }("");
        require(sent, "withdraw failed");
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

    /// @dev Mirrors the real curve: exemption keys on the buy's `recipient`
    /// and is only settable through the factory.
    mapping(address => bool) public snipeTaxExempt;
    address public factory;

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
        factory = msg.sender;
    }

    function initialize(address token_) external {
        token = token_;
    }

    function exemptFromSnipeTax(address account) external {
        require(msg.sender == factory, "OnlyFactory");
        snipeTaxExempt[account] = true;
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
    error ExemptionListTooLong();

    address public feeEscrow;
    uint256 public launchFee = 0.0005 ether;
    bool public launchEnabled = true;
    uint256 public maxCreatorTaxBps = 1000;

    /// @dev Zero until a test wires them; the buyback adapter's constructor
    /// requires both to be live contracts.
    address public memeHook;
    address public poolManager;

    mapping(address => bool) public approvedPairTokens;
    mapping(address => uint256) private _phantomQuote;
    mapping(address => uint256) private _graduationThreshold;
    mapping(address => uint8) private _decimals;
    mapping(address => IPonsV2LaunchFactory.LaunchedToken) private _launchedTokens;

    address public lastToken;
    address public lastCurve;
    /// @dev Applied to the next curve this factory creates, so a clamped buy
    /// can be arranged before the curve exists.
    uint256 public nextClamp = type(uint256).max;

    constructor(address feeEscrow_) {
        feeEscrow = feeEscrow_;
    }

    function setGraduationInfrastructure(address memeHook_, address poolManager_) external {
        memeHook = memeHook_;
        poolManager = poolManager_;
    }

    /// @dev Mirrors the real factory's launch record for tokens the tests
    /// fabricate directly instead of routing through `launchToken`.
    function registerLaunch(
        address token,
        address curve,
        address pairToken,
        uint24 poolFee,
        int24 tickSpacing,
        uint8 phase
    ) public {
        IPonsV2LaunchFactory.LaunchedToken storage record = _launchedTokens[token];
        record.token = token;
        record.curve = curve;
        record.pairToken = pairToken;
        record.poolFee = poolFee;
        record.tickSpacing = tickSpacing;
        record.phase = phase;
        record.exists = true;
    }

    function setPhase(address token, uint8 phase) external {
        _launchedTokens[token].phase = phase;
    }

    function getLaunchedToken(address token)
        external
        view
        returns (IPonsV2LaunchFactory.LaunchedToken memory)
    {
        return _launchedTokens[token];
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
        address pairToken,
        address[] calldata snipeTaxExemptions
    ) external payable returns (address token, address curve) {
        require(msg.value == launchFee, "LaunchFeeNotPaid");
        require(launchEnabled, "LaunchDisabled");
        if (snipeTaxExemptions.length > 32) revert ExemptionListTooLong();
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

        // Mirrors the real factory: the launch caller and the creator-fee
        // recipient never count as snipers on their own launch, and the
        // declared bundle wallets are exempted before trading opens.
        deployed.exemptFromSnipeTax(msg.sender);
        if (params.creatorFeeRecipient != msg.sender) {
            deployed.exemptFromSnipeTax(params.creatorFeeRecipient);
        }
        for (uint256 i = 0; i < snipeTaxExemptions.length; ++i) {
            deployed.exemptFromSnipeTax(snipeTaxExemptions[i]);
        }

        lastToken = address(launched);
        lastCurve = address(deployed);
        registerLaunch(address(launched), address(deployed), pairToken, 0, 200, 0);
        return (address(launched), address(deployed));
    }
}

interface IMockUnlockCallback {
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}

/// @dev Stands in for the Uniswap v4 singleton: `unlock` re-enters the caller,
/// `swap` reports a packed BalanceDelta at a configurable rate, `settle`
/// verifies native payment, and `take` mints the output. Records the pool key
/// so tests can assert the adapter derived the graduated pool correctly.
contract MockPoolManager {
    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    uint256 public rate = 1000;
    /// @dev When non-zero, the swap spends only this much input — the partial
    /// fill the adapter must refuse.
    uint256 public spendOverride;
    /// @dev When non-zero, the swap reports this output regardless of rate.
    uint256 public outputOverride;

    bool public unlocked;
    bool public settledDuringUnlock;
    PoolKey public lastKey;
    bool public lastZeroForOne;
    int256 public lastAmountSpecified;

    function setRate(uint256 rate_) external {
        rate = rate_;
    }

    function setSpendOverride(uint256 spend) external {
        spendOverride = spend;
    }

    function setOutputOverride(uint256 output) external {
        outputOverride = output;
    }

    function unlock(bytes calldata data) external returns (bytes memory result) {
        require(!unlocked, "AlreadyUnlocked");
        unlocked = true;
        result = IMockUnlockCallback(msg.sender).unlockCallback(data);
        require(settledDuringUnlock, "CurrencyNotSettled");
        unlocked = false;
        settledDuringUnlock = false;
    }

    function swap(PoolKey calldata key, SwapParams calldata params, bytes calldata)
        external
        returns (int256 swapDelta)
    {
        require(unlocked, "ManagerLocked");
        lastKey = key;
        lastZeroForOne = params.zeroForOne;
        lastAmountSpecified = params.amountSpecified;

        uint256 requested = uint256(-params.amountSpecified);
        uint256 spent = spendOverride != 0 ? spendOverride : requested;
        uint256 output = outputOverride != 0 ? outputOverride : spent * rate;
        // The spent leg is the swap's input currency: currency0 (upper 128
        // bits) when zeroForOne, currency1 (lower) otherwise — matching the
        // real singleton's packed BalanceDelta. The lower half must carry the
        // negative amount as its two's-complement 128-bit slice, not a
        // sign-extended full-width value that would flood the upper half.
        swapDelta = params.zeroForOne
            ? (-int256(spent) << 128) | int256(output)
            : int256((uint256(output) << 128) | uint256(uint128(int128(-int256(spent)))));
    }

    /// @dev ERC20 settlement state for the real singleton's
    /// sync → transfer → settle sequence.
    address public syncedCurrency;
    uint256 public syncedBalance;

    function sync(address currency) external {
        require(unlocked, "ManagerLocked");
        syncedCurrency = currency;
        syncedBalance = MockERC20(currency).balanceOf(address(this));
    }

    function settle() external payable returns (uint256 paid) {
        require(unlocked, "ManagerLocked");
        settledDuringUnlock = true;
        if (syncedCurrency != address(0)) {
            paid = MockERC20(syncedCurrency).balanceOf(address(this)) - syncedBalance;
            syncedCurrency = address(0);
            syncedBalance = 0;
            return paid;
        }
        return msg.value;
    }

    function take(address currency, address to, uint256 amount) external {
        require(unlocked, "ManagerLocked");
        MockERC20(currency).mint(to, amount);
    }

    receive() external payable { }
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
