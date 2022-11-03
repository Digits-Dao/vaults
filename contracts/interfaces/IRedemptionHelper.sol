// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @title IRedemptionHelper
 * @author pbnather
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRedemptionHelper {
    /* ============ Events ============ */

    event RedemptionIntervalSet(uint256 interval);

    event PreparationTimeSet(uint256 preparationTime);

    event RedemptionTokenSet(IERC20 token);

    event NewRedemption(
        uint256 indexed index,
        uint256 redemptionTime,
        uint256 registrationEndTime,
        uint256 fee,
        IERC20 indexed token
    );

    event RedemptionActivated(
        uint256 indexed index,
        uint256 indexed price,
        IERC20 token
    );

    event Reedemed(
        uint256 indexed index,
        address indexed user,
        uint256 indexed amount,
        IERC20 token
    );

    event Registered(
        uint256 indexed index,
        address indexed user,
        uint256 indexed amount,
        IERC20 token
    );

    event Unregistered(
        uint256 indexed index,
        address indexed user,
        uint256 indexed amount,
        IERC20 token
    );

    /* ============ External Functions ============ */

    function initialize(address owner_, address admin_) external;

    function redeem(uint256[] memory claims) external;

    function register(uint256 amount) external;

    function unregister(uint256 amount) external;

    /* ============ External Admin Functions ============ */

    /**
     * @dev Allows admin to change owner of the vault contract.
     *
     * @param owner_ The new owner.
     */
    function changeOwner(address owner_) external;

    /* ============ External Owner Functions ============ */

    function setRedemptionInterval(uint256 interval) external;

    function setPreparationTime(uint256 preparationTime) external;

    function initializeRedemptions(uint256 nextRedemptionExactTime, uint256 fee)
        external;

    function activateRedemption(uint256 nextRedemptionExactTime, uint256 fee)
        external;

    /* ============ External View Functions ============ */
}
