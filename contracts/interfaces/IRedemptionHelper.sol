// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @title IRedemption
 * @author pbnather
 */

interface IRedemptionHelper {
    /* ============ Events ============ */

    /* ============ External Functions ============ */

    function Redeem(uint256[] memory claims) external;

    function Register(uint256 amount) external;

    function Unregister(uint256 amount) external;

    /* ============ External Owner Functions ============ */

    function SetRedemptionInterval(uint256 interval) external;

    function SetPreparationTime(uint256 preparationTime) external;

    function Initialize(uint256 nextRedemptionExactTime) external;

    function ActivateRedemption(uint256 nextRedemptionExactTime, uint256 fee)
        external;

    /* ============ External View Functions ============ */
}
