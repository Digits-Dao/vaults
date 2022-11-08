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

    /* ============ External Admin Functions ============ */

    /**
     * @dev Allows admin to change owner of the vault contract.
     *
     * @param owner_ The new owner.
     */
    function changeOwner(address owner_) external;

    /* ============ External Owner Functions ============ */

    /**
     * @notice Set default interval between redemptions.
     *
     * @dev It can be overriden by owner on 'activateRedemption'.
     *
     * @param interval New redemption interval (in seconds).
     */
    function setRedemptionInterval(uint256 interval) external;

    /**
     * @notice Set preparation time for next redemption.
     *
     * @dev Preparation time allows users to register/unregister.
     *
     * @param preparationTime New preparation time (in seconds).
     */
    function setPreparationTime(uint256 preparationTime) external;

    /**
     * @notice Set redemption token.
     *
     * @dev Current contract supports only stablecoins.
     *
     * @param token Address of the redemption token.
     */
    function setRedemptionToken(IERC20 token) external;

    /**
     * @notice Create first redemption.
     *
     * @dev It can only be called once, before any redemptions.
     * @dev 'nextRedemptionExactTime' greater than 0 ignores '_redemptionInterval'.
     *
     * @param nextRedemptionExactTime Exact time of the new redemption (ignored if 0).
     * @param fee Fee for the new redemption (max 1000 = 10%).
     */
    function initializeRedemptions(uint256 nextRedemptionExactTime, uint256 fee)
        external;

    /**
     * @notice Activate redemption, burn registered vault tokens, transfer redemption tokens
     * from owner to the contract, allow users to redeem.
     *
     * @dev Calling this function will create next redemption object.
     * @dev 'nextRedemptionExactTime' greater than 0 ignores '_redemptionInterval'.
     *
     * @param nextRedemptionExactTime Exact time of the new redemption (ignored if 0).
     * @param fee Fee for the new redemption (max 1000 = 10%).
     */
    function activateRedemption(uint256 nextRedemptionExactTime, uint256 fee)
        external;

    /* ============ External Functions ============ */

    /**
     * @notice Initializer function called by factory.
     */
    function initialize(address owner_, address admin_) external;

    /**
     * @notice Reedem redemption tokens.
     *
     * @param claims List of redemption indexes to claim from.
     */
    function redeem(uint256[] memory claims) external;

    /**
     * @notice Register vault tokens for the current redemption.
     *
     * @dev Only works if current redemtpion 'registrationTimeEnd' hasn't passed yet.
     *
     * @param amount Amount of vault tokens to register.
     */
    function register(uint256 amount) external;

    /**
     * @notice Unegister vault tokens for the current redemption.
     *
     * @dev Only works if current redemtpion 'registrationTimeEnd' hasn't passed yet.
     *
     * @param amount Amount of vault tokens to register.
     */
    function unregister(uint256 amount) external;

    /* ============ External View Functions ============ */

    /**
     * @notice Returns amount of vault tokens registered by the user for given redemption.
     *
     * @param _user Address of the vault user.
     * @param _redemptionIndex Index of the redemption.
     *
     * @return amount Amount of tokens registered by the user.
     * @return token Address of the redemption token.
     */
    function getRegisteredAmount(address _user, uint256 _redemptionIndex)
        external
        view
        returns (uint256 amount, IERC20 token);

    /**
     * @notice Returns number of redemptions in the list.
     *
     * @return length Number of redemptions (length of redemptions list).
     */
    function getRedemptionsLength() external view returns (uint256 length);

    /**
     * @notice Returns all information of the given redemption.
     *
     * @param _redemptionIndex Index of the redemption.
     *
     * @return redemptionTime Time after which redemption can be activated.
     * @return registrationEndTime Time until users can (un)register their tokens.
     * @return pending Pending tokens to redeem.
     * @return price Redemtpion value of tokens in 'token' after 'fee'.
     * @return fee Fee taken (max 10%).
     * @return token Token address used for redemption.
     * @return active If users can redeem.
     */
    function getRedemption(uint256 _redemptionIndex)
        external
        view
        returns (
            uint256 redemptionTime,
            uint256 registrationEndTime,
            uint256 pending,
            uint256 price,
            uint256 fee,
            IERC20 token,
            bool active
        );

    /**
     * @notice Returns next redemption fee.
     *
     * @return nextRedemptionFee Next redemption fee.
     */
    function getNextRedemptionFee()
        external
        view
        returns (uint256 nextRedemptionFee);

    /**
     * @notice Returns next redemption time.
     *
     * @return nextRedemptionTime Time after which redemption can be activated.
     */
    function getNextRedemptionTime()
        external
        view
        returns (uint256 nextRedemptionTime);

    /**
     * @notice Returns if current redemption's registration period is open.
     *
     * @return registrationOpen If registration period is open.
     */
    function isRegistrationOpen() external view returns (bool registrationOpen);
}
