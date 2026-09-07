// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title TestToken
/// @notice Mock ERC-20 token for migration protocol testing and local demonstrations.
contract TestToken is ERC20, Ownable {
    constructor(string memory name, string memory symbol, address initialOwner)
        ERC20(name, symbol)
        Ownable(initialOwner)
    {}

    /// @notice Mints tokens to a recipient address.
    /// @param recipient The address receiving minted tokens.
    /// @param amount The quantity of tokens to mint.
    function mint(address recipient, uint256 amount) external onlyOwner {
        _mint(recipient, amount);
    }

    /// @notice Burns tokens from the caller's balance.
    /// @param amount The quantity of tokens to burn.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
