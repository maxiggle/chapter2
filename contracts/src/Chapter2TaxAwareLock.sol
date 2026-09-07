// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Chapter2TaxAwareLock
/// @notice Manages token locking for fee-on-transfer (taxed) ERC-20 assets using balance-delta accounting.
contract Chapter2TaxAwareLock is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable TOKEN;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    mapping(address participant => uint256) public totalLockedBalances;
    address[] private _migrationParticipants;
    mapping(address participant => bool) private _isMigrationParticipant;

    uint256 public totalAssetsLocked;
    uint256 public totalAssetsBurned;
    bool public migrationCompleted;
    uint256 public migrationBlock;

    event MigrationLocked(
        address indexed participant, uint256 nominalAmount, uint256 actualAmountReceived, uint256 blockNumber
    );
    event MigrationCompleted(uint256 indexed migrationBlock, uint256 totalBurned);
    event LockedTokensBurned(uint256 amountBurned, uint256 remainingBalance);

    constructor(address tokenAddress) Ownable(msg.sender) {
        require(tokenAddress != address(0), "Invalid token address");
        TOKEN = IERC20(tokenAddress);
    }

    /// @notice Locks tokens using balance-delta accounting to handle transfer fees accurately.
    /// @param amount The nominal quantity of tokens the caller wishes to lock.
    function lockForMigration(uint256 amount) external nonReentrant {
        require(!migrationCompleted, "Migration has already been completed");
        require(amount > 0, "You cannot store zero balance");

        uint256 balanceBefore = TOKEN.balanceOf(address(this));
        TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        uint256 actualReceived = TOKEN.balanceOf(address(this)) - balanceBefore;

        require(actualReceived > 0, "No tokens received after fee");

        if (!_isMigrationParticipant[msg.sender]) {
            _isMigrationParticipant[msg.sender] = true;
            _migrationParticipants.push(msg.sender);
        }

        totalLockedBalances[msg.sender] += actualReceived;
        totalAssetsLocked += actualReceived;

        emit MigrationLocked(msg.sender, amount, actualReceived, block.number);
    }

    /// @notice Burns all contract token reserves to dead address and finalizes migration.
    function burnLockedToBurnAddress() external onlyOwner nonReentrant {
        require(!migrationCompleted, "Migration has already been completed");
        uint256 currentBalance = TOKEN.balanceOf(address(this));
        require(currentBalance > 0, "No assets to burn");

        migrationCompleted = true;
        migrationBlock = block.number;
        totalAssetsBurned += currentBalance;

        TOKEN.safeTransfer(BURN_ADDRESS, currentBalance);
        emit MigrationCompleted(migrationBlock, totalAssetsBurned);
    }

    /// @notice Burns tokens in chunks for tokens enforcing max transaction limits (maxTxAmount).
    /// @param chunkAmount The maximum quantity of tokens to burn in this transaction.
    function burnLockedChunked(uint256 chunkAmount) external onlyOwner nonReentrant {
        require(!migrationCompleted, "Migration has already been completed");
        require(chunkAmount > 0, "Chunk amount must be greater than zero");

        uint256 currentBalance = TOKEN.balanceOf(address(this));
        require(currentBalance > 0, "No assets to burn");

        uint256 burnAmount = chunkAmount < currentBalance ? chunkAmount : currentBalance;
        totalAssetsBurned += burnAmount;

        TOKEN.safeTransfer(BURN_ADDRESS, burnAmount);

        uint256 remainingBalance = TOKEN.balanceOf(address(this));
        if (remainingBalance == 0) {
            migrationCompleted = true;
            migrationBlock = block.number;
            emit MigrationCompleted(migrationBlock, totalAssetsBurned);
        } else {
            emit LockedTokensBurned(burnAmount, remainingBalance);
        }
    }

    /// @notice Retrieves all unique migration participant addresses.
    function getMigrationParticipants() external view returns (address[] memory) {
        return _migrationParticipants;
    }

    /// @notice Gets the total amount of tokens locked by a specific participant.
    function getParticipantBalance(address participant) external view returns (uint256) {
        return totalLockedBalances[participant];
    }

    /// @notice Retrieves a paginated slice of migration participants.
    function getMigrationParticipantsPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory participants, uint256 totalParticipantCount)
    {
        uint256 total = _migrationParticipants.length;
        if (offset >= total) {
            return (new address[](0), total);
        }
        uint256 count = limit;
        unchecked {
            if (offset + count > total) {
                count = total - offset;
            }
        }
        participants = new address[](count);
        for (uint256 i = 0; i < count;) {
            participants[i] = _migrationParticipants[offset + i];
            unchecked {
                ++i;
            }
        }
        return (participants, total);
    }
}
