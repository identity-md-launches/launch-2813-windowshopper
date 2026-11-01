// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WindowShopper} from "../src/WindowShopper.sol";

/// @dev Deploys the token and performs the whole launch distribution in ONE call, the way
/// ProjectFactory.launchCustom does in one transaction: 10% to the distributor, the pool share to the
/// pool manager stand-in, the rest to the requester. Every leg is checked to arrive whole.
contract OneCallLauncher {
    struct Result {
        WindowShopper token;
        uint256 supplyAfterDeploy;
        uint256 heldAfterDeploy;
        uint256 swarmReceived;
        uint256 poolReceived;
        uint256 remainderReceived;
    }

    function launch(bytes32 salt, address distributor, address poolManager, address requester, uint256 poolBps)
        external
        returns (Result memory r)
    {
        r.token = new WindowShopper{salt: salt}();
        r.supplyAfterDeploy = r.token.totalSupply();
        r.heldAfterDeploy = r.token.balanceOf(address(this));
        uint256 supply = r.supplyAfterDeploy;
        uint256 swarm = supply * 1_000 / 10_000;
        uint256 pool = supply * poolBps / 10_000;
        uint256 remainder = supply - swarm - pool;

        uint256 before = r.token.balanceOf(distributor);
        require(r.token.transfer(distributor, swarm), "swarm transfer returned false");
        r.swarmReceived = r.token.balanceOf(distributor) - before;

        before = r.token.balanceOf(poolManager);
        require(r.token.transfer(poolManager, pool), "pool transfer returned false");
        r.poolReceived = r.token.balanceOf(poolManager) - before;

        before = r.token.balanceOf(requester);
        require(r.token.transfer(requester, remainder), "remainder transfer returned false");
        r.remainderReceived = r.token.balanceOf(requester) - before;
    }
}

contract WindowShopperAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    WindowShopper internal token;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");

    function setUp() public {
        token = new WindowShopper();
    }

    // ---------------------------------------------------------------- launch floor mirror

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_oneCallLaunchFlowsArriveWhole(bytes32 salt, uint256 rawPoolBps) public {
        uint256 poolBps = bound(rawPoolBps, 0, 9_000);
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager");
        address requester = makeAddr("requester");
        OneCallLauncher launcher = new OneCallLauncher();
        OneCallLauncher.Result memory r = launcher.launch(salt, distributor, poolManager, requester, poolBps);

        assertEq(r.supplyAfterDeploy, SUPPLY, "constructor minted the wrong supply");
        assertEq(r.heldAfterDeploy, SUPPLY, "factory did not receive the whole supply");
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * poolBps / 10_000;
        assertEq(r.swarmReceived, swarm, "swarm share arrived short");
        assertEq(r.poolReceived, pool, "pool share arrived short");
        assertEq(r.remainderReceived, SUPPLY - swarm - pool, "remainder arrived short");
        assertEq(r.token.balanceOf(address(launcher)), 0, "factory kept something back");
        assertEq(r.token.totalSupply(), SUPPLY, "launch flows changed the supply");

        // The distributor's claims arrive whole as well, down to the last wei.
        address claimant = makeAddr("claimant");
        vm.startPrank(distributor);
        assertTrue(r.token.transfer(claimant, swarm - 1));
        assertTrue(r.token.transfer(claimant, 1));
        vm.stopPrank();
        assertEq(r.token.balanceOf(claimant), swarm);
        assertEq(r.token.balanceOf(distributor), 0);
    }

    function test_create2AddressIsDeterministicAndSaltCannotBeReused() public {
        OneCallLauncher launcher = new OneCallLauncher();
        bytes32 salt = bytes32(uint256(7));
        address predicted =
            vm.computeCreate2Address(salt, keccak256(type(WindowShopper).creationCode), address(launcher));
        OneCallLauncher.Result memory r = launcher.launch(salt, alice, bob, spender, 5_000);
        assertEq(address(r.token), predicted);
        // A second launch at the same salt cannot overwrite the deployed token or re-mint it.
        vm.expectRevert();
        launcher.launch(salt, alice, bob, spender, 5_000);
        assertEq(r.token.totalSupply(), SUPPLY);
    }

    /// @dev Mirrors the floor's reachable-opcode scan of the runtime code.
    function test_runtimeCodeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        bool reachable = true;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += op - 0x5F;
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    function test_privilegedCallsFromDeployerNeitherMintNorFreeze() public {
        assertTrue(token.transfer(alice, SUPPLY / 1_000));
        string[22] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "issue(uint256)",
            "setOwner(address)",
            "unpause()",
            "pause()",
            "blocklist(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "burn(address,uint256)",
            "renounceOwnership()",
            "owner()",
            "setFee(uint256)",
            "excludeFromFee(address)",
            "rescueTokens(address,uint256)",
            "increaseAllowance(address,uint256)",
            "decreaseAllowance(address,uint256)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, type(uint128).max);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(alice);
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        // The deployer holds no implicit allowance over a holder.
        (bool moved,) =
            address(token).call(abi.encodeWithSelector(IERC20.transferFrom.selector, alice, address(this), 1));
        assertFalse(moved);
        assertEq(token.balanceOf(alice), SUPPLY / 1_000);
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(bob, SUPPLY / 2_000));
        assertEq(token.balanceOf(bob), SUPPLY / 2_000);
    }

    // ---------------------------------------------------------------- selector surface

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_unknownSelectorsRevertAndChangeNothing(bytes4 selector, bytes calldata tail, address caller)
        public
    {
        if (
            selector == IERC20.transfer.selector || selector == IERC20.transferFrom.selector
                || selector == IERC20.approve.selector || selector == IERC20.balanceOf.selector
                || selector == IERC20.allowance.selector || selector == IERC20.totalSupply.selector
                || selector == bytes4(keccak256("name()")) || selector == bytes4(keccak256("symbol()"))
                || selector == bytes4(keccak256("decimals()")) || selector == bytes4(keccak256("INITIAL_SUPPLY()"))
        ) {
            selector = bytes4(keccak256(abi.encode(selector)));
        }
        vm.prank(caller);
        (bool ok,) = address(token).call(abi.encodePacked(selector, tail));
        assertFalse(ok, "an undeclared selector was accepted");
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_emptyCalldataWithoutValueReverts() public {
        (bool ok,) = address(token).call("");
        assertFalse(ok);
    }

    // ---------------------------------------------------------------- edge cases

    function test_transferFromZeroOwnerRevertsEvenForZeroAmount() public {
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
    }

    function test_transferFromZeroOwnerWithAmountRevertsOnAllowance() public {
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(0), alice, 1);
    }

    function test_oneWeiTransferAndBack() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        token.transfer(bob, 2);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_spendingAllowanceEmitsOnlyTransfer() public {
        token.approve(spender, 100);
        vm.recordLogs();
        vm.prank(spender);
        token.transferFrom(address(this), alice, 60);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], IERC20.Transfer.selector);
        assertEq(token.allowance(address(this), spender), 40);
    }

    function test_selfApprovalIsAnOrdinaryAllowance() public {
        token.approve(address(this), 10);
        assertTrue(token.transferFrom(address(this), alice, 10));
        assertEq(token.allowance(address(this), address(this)), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
    }

    function test_tokensSentToTokenAddressAreStuckButCounted() public {
        assertTrue(token.transfer(address(token), 5));
        assertEq(token.balanceOf(address(token)), 5);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maxAllowanceStillBoundedByBalance() public {
        token.transfer(alice, 100);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 100, 101));
        token.transferFrom(alice, bob, 101);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 100);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_arbitraryHoldersTransferExactly(address from, address to, uint256 rawSeed, uint256 rawAmount)
        public
    {
        if (from == address(0)) from = alice;
        if (to == address(0)) to = bob;
        uint256 seed = bound(rawSeed, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, seed);
        token.transfer(from, seed);
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        if (from == to) {
            assertEq(token.balanceOf(from), fromBefore);
        } else {
            assertEq(token.balanceOf(from), fromBefore - amount);
            assertEq(token.balanceOf(to), toBefore + amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_overdraftAlwaysRevertsWithExactError(uint256 rawHeld, uint256 rawExtra) public {
        uint256 held = bound(rawHeld, 0, SUPPLY);
        uint256 amount = held + bound(rawExtra, 1, type(uint256).max - held);
        token.transfer(alice, held);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        token.transfer(bob, amount);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_infiniteAllowanceNeverDecreases(uint256 a, uint256 b) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, SUPPLY - a);
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, a));
        assertTrue(token.transferFrom(address(this), bob, b));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY - a - b);
    }
}

/// @dev Drives successes AND failure paths across a growing set of holders (fixed actors plus any
/// fuzzed recipient). Every failure is asserted to revert with the exact error and change nothing.
contract AdversarialHandler is Test {
    WindowShopper internal immutable token;
    address[] public holders;
    mapping(address => bool) public known;
    address[5] public actors;
    mapping(address => uint256) public modelBalance;
    mapping(address => mapping(address => uint256)) public modelAllowance;

    uint256 public ghostSucceeded;
    uint256 public ghostExpectedFailures;
    uint256 public ghostMoved;

    constructor(WindowShopper token_, address initialHolder) {
        token = token_;
        for (uint256 i; i < 5; ++i) {
            actors[i] = makeAddr(string.concat("actor", vm.toString(i)));
            _track(actors[i]);
        }
        _track(initialHolder);
        modelBalance[initialHolder] = 1_000_000_000 * 10 ** 18;
    }

    function holderCount() external view returns (uint256) {
        return holders.length;
    }

    function _track(address a) internal {
        if (!known[a]) {
            known[a] = true;
            holders.push(a);
        }
    }

    function _holder(uint256 raw) internal view returns (address) {
        return holders[raw % holders.length];
    }

    function _actor(uint256 raw) internal view returns (address) {
        return actors[raw % 5];
    }

    function _usable(address a) internal view returns (bool) {
        return a != address(0) && a != address(vm) && a != CONSOLE && a != CREATE2_FACTORY && a.code.length == 0;
    }

    function _expectFailure(bytes memory data, address caller, bytes memory expected) internal {
        vm.prank(caller);
        (bool ok, bytes memory reason) = address(token).call(data);
        assertFalse(ok, "invalid call succeeded");
        assertEq(reason, expected, "wrong revert reason");
        ++ghostExpectedFailures;
    }

    // ---- successes

    function transfer(uint256 rawFrom, uint256 rawTo, uint256 rawAmount) external {
        address from = _holder(rawFrom);
        address to = _holder(rawTo);
        uint256 amount = bound(rawAmount, 0, modelBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        modelBalance[from] -= amount;
        modelBalance[to] += amount;
        ++ghostSucceeded;
        ghostMoved += amount;
    }

    function transferToNewAddress(uint256 rawFrom, address to, uint256 rawAmount) external {
        if (!_usable(to)) to = _actor(uint160(to));
        address from = _holder(rawFrom);
        uint256 amount = bound(rawAmount, 0, modelBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _track(to);
        modelBalance[from] -= amount;
        modelBalance[to] += amount;
        ++ghostSucceeded;
        ghostMoved += amount;
    }

    function approve(uint256 rawOwner, uint256 rawSpender, uint256 amount) external {
        address owner = _holder(rawOwner);
        address spender = _actor(rawSpender);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        modelAllowance[owner][spender] = amount;
        ++ghostSucceeded;
    }

    function transferFrom(uint256 rawOwner, uint256 rawSpender, uint256 rawTo, uint256 rawAmount) external {
        address owner = _holder(rawOwner);
        address spender = _actor(rawSpender);
        address to = _holder(rawTo);
        uint256 allowed = modelAllowance[owner][spender];
        uint256 cap = modelBalance[owner] < allowed ? modelBalance[owner] : allowed;
        uint256 amount = bound(rawAmount, 0, cap);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        modelBalance[owner] -= amount;
        modelBalance[to] += amount;
        if (allowed != type(uint256).max) modelAllowance[owner][spender] = allowed - amount;
        ++ghostSucceeded;
        ghostMoved += amount;
    }

    // ---- failure paths

    function overdraw(uint256 rawFrom, uint256 rawTo, uint256 rawExtra) external {
        address from = _holder(rawFrom);
        uint256 bal = modelBalance[from];
        uint256 amount = bal + bound(rawExtra, 1, type(uint256).max - bal);
        _expectFailure(
            abi.encodeCall(IERC20.transfer, (_holder(rawTo), amount)),
            from,
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, bal, amount)
        );
    }

    function transferToZero(uint256 rawFrom, uint256 rawAmount) external {
        address from = _holder(rawFrom);
        uint256 amount = bound(rawAmount, 0, modelBalance[from]);
        _expectFailure(
            abi.encodeCall(IERC20.transfer, (address(0), amount)),
            from,
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function overspendAllowance(uint256 rawOwner, uint256 rawSpender, uint256 rawTo, uint256 rawExtra) external {
        address owner = _holder(rawOwner);
        address spender = _actor(rawSpender);
        uint256 allowed = modelAllowance[owner][spender];
        if (allowed == type(uint256).max) {
            // Infinite allowance: overspending is bounded by balance instead.
            uint256 bal = modelBalance[owner];
            uint256 over = bal + bound(rawExtra, 1, type(uint256).max - bal);
            _expectFailure(
                abi.encodeCall(IERC20.transferFrom, (owner, _holder(rawTo), over)),
                spender,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, bal, over)
            );
            return;
        }
        uint256 amount = allowed + bound(rawExtra, 1, type(uint256).max - allowed);
        _expectFailure(
            abi.encodeCall(IERC20.transferFrom, (owner, _holder(rawTo), amount)),
            spender,
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
    }

    function transferFromToZero(uint256 rawOwner, uint256 rawSpender, uint256 rawAmount) external {
        address owner = _holder(rawOwner);
        address spender = _actor(rawSpender);
        uint256 allowed = modelAllowance[owner][spender];
        uint256 cap = modelBalance[owner] < allowed ? modelBalance[owner] : allowed;
        uint256 amount = bound(rawAmount, 0, cap);
        _expectFailure(
            abi.encodeCall(IERC20.transferFrom, (owner, address(0), amount)),
            spender,
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function approveZeroSpender(uint256 rawOwner, uint256 amount) external {
        address owner = _holder(rawOwner);
        _expectFailure(
            abi.encodeCall(IERC20.approve, (address(0), amount)),
            owner,
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function tryMint(uint256 rawCaller, uint256 amount) external {
        address caller = _holder(rawCaller);
        vm.prank(caller);
        (bool ok,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", caller, amount));
        assertFalse(ok, "mint reachable");
        vm.prank(caller);
        (ok,) = address(token).call(abi.encodeWithSignature("burn(uint256)", amount));
        assertFalse(ok, "burn reachable");
        ++ghostExpectedFailures;
    }
}

contract WindowShopperAdversarialInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    WindowShopper internal token;
    AdversarialHandler internal handler;

    function setUp() public {
        token = new WindowShopper();
        handler = new AdversarialHandler(token, address(this));
        targetContract(address(handler));
        targetSender(makeAddr("sender"));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_totalSupplyFixedAndFullyHeldByTrackedHolders() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 n = handler.holderCount();
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            sum += token.balanceOf(handler.holders(i));
        }
        assertEq(sum, SUPPLY, "supply leaked outside the holders the handler sent it to");
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesAndAllowancesMatchModel() public view {
        uint256 n = handler.holderCount();
        for (uint256 i; i < n; ++i) {
            address h = handler.holders(i);
            assertEq(token.balanceOf(h), handler.modelBalance(h), "balance diverged from model");
            for (uint256 j; j < 5; ++j) {
                address s = handler.actors(j);
                assertEq(token.allowance(h, s), handler.modelAllowance(h, s), "allowance diverged from model");
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_noBalanceExceedsSupply() public view {
        uint256 n = handler.holderCount();
        for (uint256 i; i < n; ++i) {
            assertLe(token.balanceOf(handler.holders(i)), SUPPLY);
        }
    }

    /// @dev Non-vacuity: every run must have exercised at least one call, success or rejected failure.
    function afterInvariant() public view {
        assertGt(handler.ghostSucceeded() + handler.ghostExpectedFailures(), 0, "handler exercised nothing");
    }
}
