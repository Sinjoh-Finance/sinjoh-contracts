// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { MockERC20, MockPoolManager } from "./PonsV2Mocks.sol";

/// @dev Mirrors UERC20's factory-parameter construction so the mock token has
/// deterministic creation code and the factory's CREATE2 prediction works the
/// same way the real one does.
contract MockUERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    bytes32 public graffiti;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor() {
        MockPTTokenFactory.Parameters memory parameters =
            MockPTTokenFactory(msg.sender).getParameters();
        name = parameters.name;
        symbol = parameters.symbol;
        decimals = parameters.decimals;
        graffiti = parameters.graffiti;
        totalSupply = parameters.totalSupply;
        balanceOf[parameters.recipient] = parameters.totalSupply;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
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

/// @dev Deterministic CREATE2 token factory mirroring UERC20Factory's salt
/// derivation: (name, symbol, decimals, msg.sender, graffiti).
contract MockPTTokenFactory {
    struct Parameters {
        string name;
        string symbol;
        uint256 totalSupply;
        address recipient;
        uint8 decimals;
        bytes32 graffiti;
    }

    Parameters private _parameters;

    function getParameters() external view returns (Parameters memory) {
        return _parameters;
    }

    function getUERC20Address(
        string memory name,
        string memory symbol,
        uint8 decimals,
        address creator,
        bytes32 graffiti
    ) public view returns (address) {
        bytes32 salt = keccak256(abi.encode(name, symbol, decimals, creator, graffiti));
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            keccak256(type(MockUERC20).creationCode)
                        )
                    )
                )
            )
        );
    }

    function createToken(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 totalSupply,
        address recipient,
        bytes memory,
        bytes32 graffiti
    ) external returns (address tokenAddress) {
        _parameters = Parameters({
            name: name,
            symbol: symbol,
            totalSupply: totalSupply,
            recipient: recipient,
            decimals: decimals,
            graffiti: graffiti
        });
        bytes32 salt = keccak256(abi.encode(name, symbol, decimals, msg.sender, graffiti));
        tokenAddress = address(new MockUERC20{ salt: salt }());
        delete _parameters;
    }
}

interface IMockPTStrategy {
    function initializeDistribution(
        address token,
        uint256 totalSupply,
        bytes calldata configData,
        bytes32 salt
    ) external;
}

/// @dev Mirrors LiquidityLauncher v3.2.0: `multicall` delegatecalls into this
/// same contract so `msg.sender` inside `createToken`/`distributeToken` stays
/// the original caller — which is what derives the graffiti and the
/// distribution salt namespace, exactly as upstream.
contract MockPTLauncher {
    error AllowanceNotFullyConsumed();

    struct Distribution {
        address strategy;
        uint128 amount;
        bytes configData;
    }

    function getGraffiti(address originalCreator) public pure returns (bytes32) {
        return keccak256(abi.encode(originalCreator));
    }

    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool ok, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!ok) {
                if (returnData.length == 0) revert();
                assembly {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
            results[i] = returnData;
        }
    }

    function createToken(
        address factory,
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        uint128 initialSupply,
        address recipient,
        bytes calldata tokenData
    ) public payable returns (address tokenAddress) {
        tokenAddress = MockPTTokenFactory(factory)
            .createToken(
                name, symbol, decimals, initialSupply, recipient, tokenData, getGraffiti(msg.sender)
            );
    }

    function distributeToken(address token, Distribution calldata distribution, bytes32 salt)
        public
        payable
    {
        MockUERC20(token).approve(distribution.strategy, distribution.amount);
        IMockPTStrategy(distribution.strategy)
            .initializeDistribution(
                token,
                distribution.amount,
                distribution.configData,
                keccak256(abi.encode(msg.sender, salt))
            );
        if (MockUERC20(token).allowance(address(this), distribution.strategy) != 0) {
            revert AllowanceNotFullyConsumed();
        }
    }
}

/// @dev Structurally identical to the adapters' `IPTPoolManager.PoolKey`.
struct MockPoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

/// @dev v4 PositionManager stand-in: sequential tokenIds from 1, plain
/// ownership, per-position pool keys, the `poolManager()` read-back the
/// adapters' constructors cross-check, and a `modifyLiquidities` that honours
/// the fee-collection plan the LBP adapter encodes (zero-liquidity decreases
/// followed by one TAKE_PAIR).
contract MockPTPositionManager {
    address public poolManager;
    uint256 public nextTokenId = 1;

    mapping(uint256 => address) private _owners;
    mapping(uint256 => MockPoolKey) private _keys;
    mapping(uint256 => uint256) public pendingFee0;
    mapping(uint256 => uint256) public pendingFee1;

    constructor(address poolManager_) {
        poolManager = poolManager_;
    }

    function mint(address to) external returns (uint256 tokenId) {
        tokenId = nextTokenId++;
        _owners[tokenId] = to;
    }

    function mintWithKey(address to, MockPoolKey memory key) public returns (uint256 tokenId) {
        tokenId = nextTokenId++;
        _owners[tokenId] = to;
        _keys[tokenId] = key;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "NOT_MINTED");
        return owner;
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        require(_owners[tokenId] == from && msg.sender == from, "NOT_AUTHORIZED");
        _owners[tokenId] = to;
    }

    function getPoolAndPositionInfo(uint256 tokenId)
        external
        view
        returns (MockPoolKey memory poolKey, uint256 info)
    {
        return (_keys[tokenId], 0);
    }

    /// @dev Tests park accrued fees per position; a fee-collection plan pays
    /// them out. Fund this contract with the native/token side first.
    function accrueFees(uint256 tokenId, uint256 amount0, uint256 amount1) external payable {
        pendingFee0[tokenId] += amount0;
        pendingFee1[tokenId] += amount1;
    }

    function modifyLiquidities(bytes calldata unlockData, uint256) external payable {
        (bytes memory actions, bytes[] memory params) = abi.decode(unlockData, (bytes, bytes[]));
        uint256 owed0;
        uint256 owed1;
        for (uint256 i = 0; i < actions.length; i++) {
            uint8 action = uint8(actions[i]);
            if (action == 0x01) {
                // DECREASE_LIQUIDITY with zero liquidity: credit accrued fees.
                (uint256 tokenId, uint256 liquidity,,,) =
                    abi.decode(params[i], (uint256, uint256, uint128, uint128, bytes));
                require(liquidity == 0, "UNEXPECTED_LIQUIDITY");
                require(_owners[tokenId] == msg.sender, "NOT_OWNER");
                owed0 += pendingFee0[tokenId];
                owed1 += pendingFee1[tokenId];
                pendingFee0[tokenId] = 0;
                pendingFee1[tokenId] = 0;
            } else if (action == 0x11) {
                // TAKE_PAIR: pay both accumulated sides to the recipient.
                (address currency0, address currency1, address recipient) =
                    abi.decode(params[i], (address, address, address));
                _pay(currency0, recipient, owed0);
                _pay(currency1, recipient, owed1);
                owed0 = 0;
                owed1 = 0;
            } else {
                revert("UNEXPECTED_ACTION");
            }
        }
    }

    function _pay(address currency, address recipient, uint256 amount) private {
        if (amount == 0) return;
        if (currency == address(0)) {
            (bool sent,) = payable(recipient).call{ value: amount }("");
            require(sent, "NATIVE_PAY_FAILED");
        } else {
            MockUERC20(currency).transfer(recipient, amount);
        }
    }

    /// @dev Test helper for feeRoutingIntact's broken-custody branch.
    function forceOwner(uint256 tokenId, address to) external {
        _owners[tokenId] = to;
    }

    receive() external payable { }
}

/// @dev FeeSplitter stand-in: tests park a pending native amount per position;
/// `collectFees` pushes it to the vault attributed to the tokenId, mirroring
/// the real 40%-native split arriving via `onAmountsReceived`.
contract MockPTFeeSplitter {
    address public positionManager;
    MockPTBeneficiaryVault public vault;

    mapping(uint256 => uint256) public pendingNative;
    uint256 public collectCalls;

    constructor(address positionManager_) {
        positionManager = positionManager_;
    }

    function setVault(MockPTBeneficiaryVault vault_) external {
        vault = vault_;
    }

    function accrue(uint256 tokenId) external payable {
        pendingNative[tokenId] += msg.value;
    }

    function collectFees(uint256[] calldata tokenIds) external {
        collectCalls++;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 amount = pendingNative[tokenIds[i]];
            if (amount == 0) continue;
            pendingNative[tokenIds[i]] = 0;
            if (address(vault) != address(0)) {
                vault.notifyAmounts{ value: amount }(tokenIds[i]);
            }
        }
    }

    receive() external payable { }
}

/// @dev UERC20BeneficiaryVault stand-in: solady-style `ownerOf` that reverts
/// for an unregistered position, owner-only `claim` that pays attributed
/// native and treats zero accrual as a no-op.
contract MockPTBeneficiaryVault {
    error TokenDoesNotExist();
    error NotBeneficiary(uint256 tokenId, address caller);
    error NotPositionOwner(uint256 tokenId, address caller);

    address public positionManager;

    mapping(uint256 => address) private _owners;
    mapping(uint256 => uint256) public attributedNative;

    constructor(address positionManager_) {
        positionManager = positionManager_;
    }

    function registerBeneficiary(uint256 tokenId, address beneficiary) external {
        if (MockPTPositionManager(payable(positionManager)).ownerOf(tokenId) != msg.sender) {
            revert NotPositionOwner(tokenId, msg.sender);
        }
        _owners[tokenId] = beneficiary;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address owner = _owners[tokenId];
        if (owner == address(0)) revert TokenDoesNotExist();
        return owner;
    }

    function notifyAmounts(uint256 tokenId) external payable {
        attributedNative[tokenId] += msg.value;
    }

    function claim(uint256 tokenId, uint256, uint256) external {
        if (msg.sender != _owners[tokenId]) revert NotBeneficiary(tokenId, msg.sender);
        uint256 amount = attributedNative[tokenId];
        if (amount == 0) return;
        attributedNative[tokenId] = 0;
        (bool sent,) = payable(msg.sender).call{ value: amount }("");
        require(sent, "claim transfer failed");
    }

    /// @dev Test helper for feeRoutingIntact's broken-custody branch.
    function forceOwner(uint256 tokenId, address to) external {
        _owners[tokenId] = to;
    }

    receive() external payable { }
}

/// @dev InstantLaunchStrategy stand-in with the real strategy's read-backs and
/// launch effects: pulls the supply, mints the position, registers the
/// beneficiary, and locks the position in the splitter. Sabotage switches let
/// tests break each custody fact the adapter verifies.
contract MockPTInstantStrategy {
    error OnlyLauncher();
    error InvalidSupply();

    uint256 public constant TOTAL_SUPPLY = 1_000_000_000e18;
    uint24 public constant LP_FEE = 2_500;
    int24 public constant TICK_SPACING = 25;
    int24 public constant initialTick = 198_050;

    address public launcher;
    address public positionManager;
    address public poolManager;
    address public feeSplitter;
    address public beneficiaryVault;

    /// @dev When set, the FEEB NFT is registered to this address instead of
    /// the configured beneficiary.
    address public beneficiaryOverride;
    /// @dev When set, the position is left with this owner instead of the
    /// splitter.
    address public positionOwnerOverride;

    uint256 public launches;
    uint256 public lastTokenId;
    bytes32 public lastSalt;

    constructor(
        address launcher_,
        address positionManager_,
        address poolManager_,
        address feeSplitter_,
        address beneficiaryVault_
    ) {
        launcher = launcher_;
        positionManager = positionManager_;
        poolManager = poolManager_;
        feeSplitter = feeSplitter_;
        beneficiaryVault = beneficiaryVault_;
    }

    function setBeneficiaryOverride(address beneficiary) external {
        beneficiaryOverride = beneficiary;
    }

    function setPositionOwnerOverride(address owner) external {
        positionOwnerOverride = owner;
    }

    function initializeDistribution(
        address token,
        uint256 totalSupply,
        bytes calldata configData,
        bytes32 salt
    ) external {
        if (msg.sender != launcher) revert OnlyLauncher();
        if (totalSupply != TOTAL_SUPPLY || MockUERC20(token).totalSupply() != TOTAL_SUPPLY) {
            revert InvalidSupply();
        }
        address feeBeneficiary = abi.decode(configData, (address));

        MockUERC20(token).transferFrom(msg.sender, address(this), totalSupply);

        uint256 tokenId = MockPTPositionManager(payable(positionManager)).mint(address(this));
        lastTokenId = tokenId;
        lastSalt = salt;
        launches++;

        if (beneficiaryVault != address(0)) {
            address beneficiary =
                beneficiaryOverride != address(0) ? beneficiaryOverride : feeBeneficiary;
            MockPTBeneficiaryVault(payable(beneficiaryVault))
                .registerBeneficiary(tokenId, beneficiary);
        }

        address finalOwner =
            positionOwnerOverride != address(0) ? positionOwnerOverride : feeSplitter;
        MockPTPositionManager(payable(positionManager))
            .transferFrom(address(this), finalOwner, tokenId);
    }
}

/// @dev Structurally identical to the adapters' `PTMigratorParameters`.
struct MockMigratorParameters {
    address token;
    address currency;
    uint64 migrationBlock;
    uint128 reservedTokenAmountForLP;
    address recipient;
    address positionRecipient;
    MockPoolParameters poolParameters;
    bytes positionDefinitions;
    bytes lpAllocationSchedule;
}

struct MockPoolParameters {
    uint24 fee;
    int24 tickSpacing;
    address hook;
}

struct MockAuctionParameters {
    address currency;
    address tokensRecipient;
    address fundsRecipient;
    uint64 startBlock;
    uint64 endBlock;
    uint64 claimBlock;
    uint256 tickSpacing;
    address validationHook;
    uint256 floorPrice;
    uint128 requiredCurrencyRaised;
    bytes auctionStepsData;
}

/// @dev Continuous clearing auction stand-in with the two benign sweep
/// refusals the adapter must tolerate, spelled with the real error names so
/// the selectors match.
contract MockPTAuction {
    error AuctionIsNotOver();
    error CannotSweepTokens();
    error NotAuthorized(address authorized, address caller);

    address public token;
    address public currency;
    address public tokensRecipient;
    address public fundsRecipient;
    uint64 public endBlock;

    uint256 public unsoldTokens;
    bool public swept;
    uint256 public raisedNative;
    uint256 public raisedCurrency;

    constructor() {
        MockPTAuctionFactory.Parameters memory parameters =
            MockPTAuctionFactory(msg.sender).getParameters();
        token = parameters.token;
        currency = parameters.currency;
        tokensRecipient = parameters.tokensRecipient;
        fundsRecipient = parameters.fundsRecipient;
        endBlock = parameters.endBlock;
    }

    /// @dev Tests park the raise here before migration.
    function fundRaise(uint256 amount) external payable {
        if (currency == address(0)) {
            raisedNative += msg.value;
        } else {
            MockUERC20(currency).transferFrom(msg.sender, address(this), amount);
            raisedCurrency += amount;
        }
    }

    function setUnsoldTokens(uint256 amount) external {
        unsoldTokens = amount;
    }

    function sweepCurrency() external {
        require(msg.sender == fundsRecipient, "NOT_FUNDS_RECIPIENT");
        if (currency == address(0)) {
            uint256 amount = raisedNative;
            raisedNative = 0;
            (bool sent,) = payable(msg.sender).call{ value: amount }("");
            require(sent, "SWEEP_FAILED");
        } else {
            uint256 amount = raisedCurrency;
            raisedCurrency = 0;
            MockUERC20(currency).transfer(msg.sender, amount);
        }
    }

    function sweepUnsoldTokens() external {
        if (block.number < endBlock) revert AuctionIsNotOver();
        if (msg.sender != tokensRecipient) revert NotAuthorized(tokensRecipient, msg.sender);
        if (swept) revert CannotSweepTokens();
        swept = true;
        uint256 amount = unsoldTokens;
        unsoldTokens = 0;
        if (amount != 0) {
            MockUERC20(token).transfer(msg.sender, amount);
        }
    }

    receive() external payable { }
}

/// @dev CCA factory stand-in: deterministic CREATE2 deploys with parameter
/// hand-off, mirroring `create`/`getAddress` agreement, plus a sabotage
/// override for the adapter's read-back verification tests.
contract MockPTAuctionFactory {
    struct Parameters {
        address token;
        address currency;
        address tokensRecipient;
        address fundsRecipient;
        uint64 endBlock;
    }

    Parameters private _parameters;
    /// @dev When set, deployed auctions bind this tokens recipient instead of
    /// the configured one — the misconfiguration the adapter must detect.
    address public tokensRecipientOverride;

    function getParameters() external view returns (Parameters memory) {
        return _parameters;
    }

    function setTokensRecipientOverride(address recipient) external {
        tokensRecipientOverride = recipient;
    }

    function _salt(address token, uint256 amount, bytes memory configData, bytes32 salt)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(token, amount, keccak256(configData), salt));
    }

    function create(address token, uint256 amount, bytes calldata configData, bytes32 salt)
        external
        returns (address distributor)
    {
        MockAuctionParameters memory auctionParams = abi.decode(configData, (MockAuctionParameters));
        _parameters = Parameters({
            token: token,
            currency: auctionParams.currency,
            tokensRecipient: tokensRecipientOverride != address(0)
                ? tokensRecipientOverride
                : auctionParams.tokensRecipient,
            fundsRecipient: auctionParams.fundsRecipient,
            endBlock: auctionParams.endBlock
        });
        distributor = address(new MockPTAuction{ salt: _salt(token, amount, configData, salt) }());
        delete _parameters;
    }

    function getAddress(
        address token,
        uint256 amount,
        bytes calldata configData,
        bytes32 salt,
        address
    ) external view returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            _salt(token, amount, configData, salt),
                            keccak256(type(MockPTAuction).creationCode)
                        )
                    )
                )
            )
        );
    }
}

/// @dev LBPStrategy stand-in: registers the auction via the factory, pulls
/// the supply split, and migrates with configurable outcome — success mints
/// positions to the configured recipient at the committed (or fallback) pool
/// key and sweeps the raise to the recipient; failure refunds raise and
/// reserve, minting nothing, exactly like the real catch branch.
contract MockPTLBPStrategy {
    error OnlyLauncher();
    error MigrationNotYetAllowed(uint256 migrationBlock, uint256 currentBlock);
    error InitializerNotRegistered(address initializer);

    address public launcher;
    address public positionManager;
    address public poolManager;
    address public initializerFactory;

    mapping(address => MockMigratorParameters) private _initializers;
    mapping(address => bool) private _migratable;

    bool public failMigration;
    bool public useStrategyHookFallback;
    uint256 public positionsToMint = 2;
    uint256 public reserveRefund;

    constructor(
        address launcher_,
        address positionManager_,
        address poolManager_,
        address initializerFactory_
    ) {
        launcher = launcher_;
        positionManager = positionManager_;
        poolManager = poolManager_;
        initializerFactory = initializerFactory_;
    }

    function setFailMigration(bool fail) external {
        failMigration = fail;
    }

    function setUseStrategyHookFallback(bool use) external {
        useStrategyHookFallback = use;
    }

    function setPositionsToMint(uint256 count) external {
        positionsToMint = count;
    }

    function setReserveRefund(uint256 amount) external {
        reserveRefund = amount;
    }

    function initializers(address initializer)
        external
        view
        returns (MockMigratorParameters memory)
    {
        return _initializers[initializer];
    }

    function initializeDistribution(
        address token,
        uint256 totalSupply,
        bytes calldata configData,
        bytes32 salt
    ) external {
        if (msg.sender != launcher) revert OnlyLauncher();
        (MockMigratorParameters memory migrationParams, bytes memory initializerParams) =
            abi.decode(configData, (MockMigratorParameters, bytes));

        uint256 auctionSupply = totalSupply - migrationParams.reservedTokenAmountForLP;
        bytes32 initializerSalt = keccak256(abi.encode(salt, migrationParams));
        address initializer = MockPTAuctionFactory(initializerFactory)
            .create(token, auctionSupply, initializerParams, initializerSalt);

        _initializers[initializer] = migrationParams;
        _migratable[initializer] = true;

        MockUERC20(token).transferFrom(msg.sender, initializer, auctionSupply);
        MockUERC20(token)
            .transferFrom(msg.sender, address(this), migrationParams.reservedTokenAmountForLP);
    }

    function migrate(address initializer) external {
        MockMigratorParameters memory migrationParams = _initializers[initializer];
        if (!_migratable[initializer]) revert InitializerNotRegistered(initializer);
        if (block.number < migrationParams.migrationBlock) {
            revert MigrationNotYetAllowed(migrationParams.migrationBlock, block.number);
        }
        _migratable[initializer] = false;

        MockPTAuction(payable(initializer)).sweepCurrency();

        if (failMigration) {
            _sendCurrency(migrationParams.currency, migrationParams.recipient);
            MockUERC20(migrationParams.token)
                .transfer(migrationParams.recipient, migrationParams.reservedTokenAmountForLP);
            return;
        }

        address token = migrationParams.token;
        address currency = migrationParams.currency;
        (address currency0, address currency1) =
            currency < token ? (currency, token) : (token, currency);
        MockPoolKey memory key = MockPoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: migrationParams.poolParameters.fee,
            tickSpacing: migrationParams.poolParameters.tickSpacing,
            hooks: migrationParams.poolParameters.hook == address(0) && useStrategyHookFallback
                ? address(this)
                : migrationParams.poolParameters.hook
        });
        for (uint256 i = 0; i < positionsToMint; i++) {
            MockPTPositionManager(payable(positionManager))
                .mintWithKey(migrationParams.positionRecipient, key);
        }

        // The non-LP raise share and any unused reserve go to the recipient.
        _sendCurrency(currency, migrationParams.recipient);
        if (reserveRefund != 0) {
            MockUERC20(token).transfer(migrationParams.recipient, reserveRefund);
        }
    }

    function _sendCurrency(address currency, address recipient) private {
        if (currency == address(0)) {
            uint256 amount = address(this).balance;
            if (amount == 0) return;
            (bool sent,) = payable(recipient).call{ value: amount }("");
            require(sent, "SEND_FAILED");
        } else {
            uint256 amount = MockUERC20(currency).balanceOf(address(this));
            if (amount == 0) return;
            MockUERC20(currency).transfer(recipient, amount);
        }
    }

    receive() external payable { }
}

/// @dev MockPoolManager plus the `extsload` slot0 read the buyback adapter
/// uses to confirm an instant pool exists.
contract MockPTBuybackPoolManager is MockPoolManager {
    mapping(bytes32 => bytes32) private _slots;

    function setSlot(bytes32 slot, bytes32 value) external {
        _slots[slot] = value;
    }

    function extsload(bytes32 slot) external view returns (bytes32) {
        return _slots[slot];
    }
}

/// @dev Minimal LBP registry + adapter views for the buyback route.
contract MockLBPRegistry {
    address public lbpStrategy;
    mapping(address => address) public adapterForSubject;

    constructor(address lbpStrategy_) {
        lbpStrategy = lbpStrategy_;
    }

    function setAdapter(address subject, address adapter) external {
        adapterForSubject[subject] = adapter;
    }
}

contract MockLBPAdapterView {
    bool public migrated;
    address public currency0;
    address public currency1;
    uint24 public fee;
    int24 public tickSpacing;
    address public hooks;

    function set(
        bool migrated_,
        address currency0_,
        address currency1_,
        uint24 fee_,
        int24 tickSpacing_,
        address hooks_
    ) external {
        migrated = migrated_;
        currency0 = currency0_;
        currency1 = currency1_;
        fee = fee_;
        tickSpacing = tickSpacing_;
        hooks = hooks_;
    }

    function poolKey() external view returns (address, address, uint24, int24, address) {
        return (currency0, currency1, fee, tickSpacing, hooks);
    }
}

/// @dev MerkleClaimFactory stand-in: pulls the leg's tokens and records the
/// decoded config, mirroring the real deploy-and-fund flow without the
/// embedded distributor bytecode.
contract MockMerkleClaimFactory {
    struct Leg {
        address token;
        uint256 amount;
        bytes32 merkleRoot;
        address owner;
        uint256 endTime;
        bytes32 salt;
    }

    Leg[] public legs;

    function legCount() external view returns (uint256) {
        return legs.length;
    }

    function initializeDistribution(
        address token,
        uint256 totalSupply,
        bytes calldata configData,
        bytes32 salt
    ) external {
        (bytes32 merkleRoot, address owner, uint256 endTime) =
            abi.decode(configData, (bytes32, address, uint256));
        MockUERC20(token).transferFrom(msg.sender, address(this), totalSupply);
        legs.push(
            Leg({
                token: token,
                amount: totalSupply,
                merkleRoot: merkleRoot,
                owner: owner,
                endTime: endTime,
                salt: salt
            })
        );
    }
}

/// @dev Pool manager stand-in for the sell direction: slot0 storage for
/// existence/price reads, the sync -> transfer -> settle ERC20 sequence, and
/// a `take` that pays native for the zero currency.
contract MockPTSellPoolManager {
    uint256 public rate = 1000;
    bool public unlocked;
    bool private settled;
    address private syncedCurrency;
    uint256 private syncedBalance;

    mapping(bytes32 => bytes32) private _slots;

    function setRate(uint256 rate_) external {
        rate = rate_;
    }

    function setSlot(bytes32 slot, bytes32 value) external {
        _slots[slot] = value;
    }

    function extsload(bytes32 slot) external view returns (bytes32) {
        return _slots[slot];
    }

    function unlock(bytes calldata data) external returns (bytes memory result) {
        require(!unlocked, "AlreadyUnlocked");
        unlocked = true;
        result = IMockUnlockCallbackSell(msg.sender).unlockCallback(data);
        require(settled, "CurrencyNotSettled");
        unlocked = false;
        settled = false;
    }

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

    function swap(PoolKey calldata, SwapParams calldata params, bytes calldata)
        external
        view
        returns (int256 swapDelta)
    {
        require(unlocked, "ManagerLocked");
        uint256 spent = uint256(-params.amountSpecified);
        uint256 output = spent * rate;
        // Selling currency1 (oneForZero): amount1 negative in the low half,
        // amount0 positive in the high half; the reverse for zeroForOne.
        swapDelta = params.zeroForOne
            ? (-int256(spent) << 128) | int256(output)
            : int256((uint256(output) << 128) | uint256(uint128(int128(-int256(spent)))));
    }

    function sync(address currency) external {
        require(unlocked, "ManagerLocked");
        syncedCurrency = currency;
        syncedBalance = MockUERC20(currency).balanceOf(address(this));
    }

    function settle() external payable returns (uint256 paid) {
        require(unlocked, "ManagerLocked");
        settled = true;
        if (syncedCurrency != address(0)) {
            paid = MockUERC20(syncedCurrency).balanceOf(address(this)) - syncedBalance;
            syncedCurrency = address(0);
            syncedBalance = 0;
            return paid;
        }
        return msg.value;
    }

    function take(address currency, address to, uint256 amount) external {
        require(unlocked, "ManagerLocked");
        if (currency == address(0)) {
            (bool sent,) = payable(to).call{ value: amount }("");
            require(sent, "NATIVE_TAKE_FAILED");
        } else {
            MockUERC20(currency).mint(to, amount);
        }
    }

    receive() external payable { }
}

interface IMockUnlockCallbackSell {
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}

/// @dev SwapRouter02 stand-in for the currency-to-WETH hop.
contract MockPTV3SwapRouter {
    uint256 public rate = 2;
    uint24 public lastFee;

    function setRate(uint256 rate_) external {
        rate = rate_;
    }

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut)
    {
        lastFee = params.fee;
        MockUERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        amountOut = params.amountIn * rate;
        require(amountOut >= params.amountOutMinimum, "TooLittleReceived");
        MockUERC20(params.tokenOut).mint(params.recipient, amountOut);
    }
}

/// @dev Shared v3 TWAP guard stand-in: a pinned fee tier and a linear quote.
contract MockSharedTwapGuard {
    uint24 public poolFee = 10_000;
    uint256 public rate = 2;

    function setPoolFee(uint24 fee) external {
        poolFee = fee;
    }

    function setRate(uint256 rate_) external {
        rate = rate_;
    }

    function quoteAtTwap(address, address, uint128 amountIn) external view returns (uint256) {
        return uint256(amountIn) * rate;
    }
}
