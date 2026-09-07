// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title TestTaxToken
/// @notice Mock fee-on-transfer ERC-20 token for testing tax-aware migration edge cases.
contract TestTaxToken is ERC20, Ownable {
    uint256 public feeBasisPoints;
    address public feeRecipient;

    uint256 public constant MAX_FEE_BPS = 10_000; // 100% maximum in basis points
    uint256 public constant BASIS_POINTS_DIVISOR = 10_000;

    event FeeConfigUpdated(uint256 feeBasisPoints, address feeRecipient);

    constructor(
        string memory name,
        string memory symbol,
        address initialOwner,
        uint256 feeBasisPoints_,
        address feeRecipient_
    ) ERC20(name, symbol) Ownable(initialOwner) {
        require(feeBasisPoints_ <= MAX_FEE_BPS, "Fee exceeds maximum");
        feeBasisPoints = feeBasisPoints_;
        feeRecipient = feeRecipient_;
    }

    /// @notice Updates the transfer fee basis points and recipient address.
    function setFeeConfig(uint256 newFeeBasisPoints, address newFeeRecipient) external onlyOwner {
        require(newFeeBasisPoints <= MAX_FEE_BPS, "Fee exceeds maximum");
        feeBasisPoints = newFeeBasisPoints;
        feeRecipient = newFeeRecipient;
        emit FeeConfigUpdated(newFeeBasisPoints, newFeeRecipient);
    }

    /// @notice Mints tokens to a recipient address.
    function mint(address recipient, uint256 amount) external onlyOwner {
        _mint(recipient, amount);
    }

    /// @dev OpenZeppelin v5 transfer hook with fee deduction.
    function _update(address from, address to, uint256 value) internal virtual override {
        if (from == address(0) || to == address(0) || feeBasisPoints == 0 || feeRecipient == address(0)) {
            super._update(from, to, value);
            return;
        }

        uint256 fee = Math.mulDiv(value, feeBasisPoints, BASIS_POINTS_DIVISOR);
        uint256 netAmount = value - fee;

        if (fee > 0) {
            super._update(from, feeRecipient, fee);
        }
        super._update(from, to, netAmount);
    }
}
