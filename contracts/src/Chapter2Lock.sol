// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Chapter2Lock
/// @notice Manages token locking for migration, tracking participant balances and burning locked tokens upon migration completion.
contract Chapter2Lock is Ownable, ReentrancyGuard {
    constructor(address _token) Ownable(msg.sender) {
        require(_token != address(0), "invalid token address");
        token = IERC20(_token);
    }

    mapping(address => uint256) public totalLockedBalances;
    address[] private _migrationParticipant;
    mapping(address => bool) private _isMigrationParticipant;

    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    bool public migrationCompleted;
    uint256 public migrationBlock;
    uint256 public totalAssetsLocked;

    event MigrationLocked(address indexed user, uint256 amount, uint256 blockNumber);
    event Unlocked(address indexed user, uint256 amount);
    event MigrationCompleted(uint256 indexed migrationBlock, uint256 totalLocked);

    /// @notice Locks a specified amount of tokens from the caller for migration.
    /// @dev Reverts if migration is already completed or if amount is 0.
    ///      Transfers tokens using SafeERC20 and records new participants.
    /// @param amount The amount of tokens to deposit and lock.
    function lockForMigration(uint256 amount) external nonReentrant {
        require(!migrationCompleted, "Migration has already been completed");
        require(amount > 0, "You cannot store zero balance");

        token.safeTransferFrom(msg.sender, address(this), amount);

        if (!_isMigrationParticipant[msg.sender]) {
            _isMigrationParticipant[msg.sender] = true;
            _migrationParticipant.push(msg.sender);
        }

        totalLockedBalances[msg.sender] += amount;
        totalAssetsLocked += amount;

        emit MigrationLocked(msg.sender, amount, block.number);
    }

    /// @notice Burns all locked tokens by sending them to the dead address and finalizes migration.
    /// @dev Can only be called by the contract owner. Marks migration as completed and captures the block number.
    function burnLockedToBurnAddress() external onlyOwner nonReentrant {
        require(!migrationCompleted, "Migration has already been completed");
        require(totalAssetsLocked > 0, "No assets to burn");

        migrationCompleted = true;
        migrationBlock = block.number;
        token.safeTransfer(BURN_ADDRESS, totalAssetsLocked);
        emit MigrationCompleted(migrationBlock, totalAssetsLocked);
    }

    /// @notice Retrieves the complete array of migration participants.
    /// @dev For large sets of participants, consider using `getMigrationParticipantsPaginated` to avoid out-of-gas errors.
    /// @return An array containing addresses of all unique migration participants.
    function getMigrationParticipants() external view returns (address[] memory) {
        return _migrationParticipant;
    }

    /// @notice Gets the total amount of tokens locked by a specific participant.
    /// @param participant The address of the user to query.
    /// @return The total locked balance of the specified user.
    function getParticipantBalance(address participant) external view returns (uint256) {
        return totalLockedBalances[participant];
    }

    /// @notice Retrieves a paginated slice of migration participants.
    /// @dev Wraps internal pagination logic to query participants safely in bounded slices.
    /// @param offset The zero-indexed starting position.
    /// @param limit The maximum number of participants to retrieve.
    /// @return participants An array containing the participant addresses for the requested slice.
    /// @return totalParticipantCount The total count of all unique migration participants.
    function getMigrationParticipantsPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory participants, uint256 totalParticipantCount)
    {
        return getPaginated(_migrationParticipant, offset, limit);
    }

    /// @notice Helper to retrieve a paginated slice from an address storage array.
    function getPaginated(address[] storage arr, uint256 offset, uint256 limit)
        internal
        view
        returns (address[] memory result, uint256 total)
    {
        total = arr.length;
        if (offset >= total) {
            return (new address[](0), total);
        }
        uint256 count = limit;
        unchecked {
            if (offset + count > total) {
                count = total - offset;
            }
        }
        result = new address[](count);
        for (uint256 i = 0; i < count;) {
            result[i] = arr[offset + i];
            unchecked {
                ++i;
            }
        }
    }
}
