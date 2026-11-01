// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {WindowShopper} from "../src/WindowShopper.sol";

/// @dev An independent balance/allowance model for sequences involving four holders.
/// All supply stays among these holders, including during delegated and self transfers.
contract WindowShopperHandler is Test {
    WindowShopper internal immutable token;
    address[4] public actors;
    uint256[4] public modelBalances;
    mapping(uint256 owner => mapping(uint256 spender => uint256 amount)) public modelAllowances;

    constructor(WindowShopper token_) {
        token = token_;
        actors[0] = makeAddr("holder zero");
        actors[1] = makeAddr("holder one");
        actors[2] = makeAddr("holder two");
        actors[3] = makeAddr("holder three");
        modelBalances[0] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 rawFrom, uint256 rawTo, uint256 rawAmount) external {
        uint256 from = rawFrom % actors.length;
        uint256 to = rawTo % actors.length;
        uint256 amount = bound(rawAmount, 0, modelBalances[from]);
        vm.prank(actors[from]);
        assertTrue(token.transfer(actors[to], amount));
        modelBalances[from] -= amount;
        modelBalances[to] += amount;
    }

    function approve(uint256 rawOwner, uint256 rawSpender, uint256 amount) external {
        uint256 owner = rawOwner % actors.length;
        uint256 spender = rawSpender % actors.length;
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], amount));
        modelAllowances[owner][spender] = amount;
    }

    function transferFrom(uint256 rawOwner, uint256 rawSpender, uint256 rawTo, uint256 rawAmount) external {
        uint256 owner = rawOwner % actors.length;
        uint256 spender = rawSpender % actors.length;
        uint256 to = rawTo % actors.length;
        uint256 allowed = modelAllowances[owner][spender];
        uint256 available = modelBalances[owner] < allowed ? modelBalances[owner] : allowed;
        uint256 amount = bound(rawAmount, 0, available);
        vm.prank(actors[spender]);
        assertTrue(token.transferFrom(actors[owner], actors[to], amount));
        modelBalances[owner] -= amount;
        modelBalances[to] += amount;
        if (allowed != type(uint256).max) {
            modelAllowances[owner][spender] -= amount;
        }
    }
}

contract WindowShopperInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    WindowShopper internal token;
    WindowShopperHandler internal handler;

    function setUp() public {
        token = new WindowShopper();
        handler = new WindowShopperHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = WindowShopperHandler.transfer.selector;
        selectors[1] = WindowShopperHandler.approve.selector;
        selectors[2] = WindowShopperHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyIsConstantAndFullyAccountedFor() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_balancesAndAllowancesMatchIndependentModel() public view {
        for (uint256 i; i < 4; ++i) {
            assertEq(token.balanceOf(handler.actors(i)), handler.modelBalances(i));
            for (uint256 j; j < 4; ++j) {
                assertEq(token.allowance(handler.actors(i), handler.actors(j)), handler.modelAllowances(i, j));
            }
        }
    }

    function invariant_metadataRemainsFixed() public view {
        assertEq(token.name(), "WindowShopper");
        assertEq(token.symbol(), "WWW");
        assertEq(token.decimals(), 18);
    }
}
