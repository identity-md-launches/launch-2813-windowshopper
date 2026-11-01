// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title WindowShopper
/// @notice Fixed-supply WWW token. The deploying caller receives the entire supply.
contract WindowShopper is ERC20 {
    /// @notice One billion WWW, expressed in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("WindowShopper", "WWW") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
