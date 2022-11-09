// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @title RedemptionHelper
 * @author pbnather
 */

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "./interfaces/IRedemptionHelper.sol";
import "./interfaces/IManagedVault.sol";

contract RedemptionHelper is IRedemptionHelper, Ownable, Initializable {
    using SafeERC20 for IERC20;

    /* ============ Structures ============ */

    struct Redemption {
        // Time after which redemption can be activated.
        uint256 redemptionTime;
        // Time until users can (un)register their tokens.
        uint256 registrationEndTime;
        // Pending tokens to redeem.
        uint256 pending;
        // Redemtpion value of tokens in 'token' after 'fee'.
        uint256 price;
        // Fee taken (max 10%).
        uint256 fee;
        // Token address used for redemption.
        IERC20 token;
        // If users can redeem.
        bool active;
    }

    /* ============ State Variables ============ */

    Redemption[] public redemptions;
    mapping(address => mapping(uint256 => uint256)) public userClaims;

    IERC20 public vault;
    address public admin;
    uint256 private _preparationTime;
    uint256 private _redemptionInterval;
    IERC20 private _redemptionToken;

    /* ============ Initializer ============ */

    /**
     * @notice Initializer function called by factory.
     */
    function initialize(
        address owner_,
        address admin_,
        address vault_
    ) external initializer {
        require(owner_ != address(0));
        require(admin_ != address(0));
        require(vault_ != address(0));
        _transferOwnership(owner_);
        admin = admin_;
        vault = IERC20(vault_);
    }

    /* ============ External Admin Functions ============ */

    /**
     * @dev Allows admin to change owner of the vault contract.
     *
     * @param owner_ The new owner.
     */
    function changeOwner(address owner_) external {
        require(msg.sender == admin);
        require(owner_ != owner());
        _transferOwnership(owner_);
    }

    /* ============ External Owner Functions ============ */

    /**
     * @notice Set default interval between redemptions.
     *
     * @dev It can be overriden by owner on 'activateRedemption'.
     *
     * @param interval New redemption interval (in seconds).
     */
    function setRedemptionInterval(uint256 interval) external onlyOwner {
        require(interval > 0);
        require(interval > _preparationTime);
        _redemptionInterval = interval;
        emit RedemptionIntervalSet(interval);
    }

    /**
     * @notice Set preparation time for next redemption.
     *
     * @dev Preparation time allows users to register/unregister.
     *
     * @param preparationTime New preparation time (in seconds).
     */
    function setPreparationTime(uint256 preparationTime) external onlyOwner {
        require(preparationTime > 0);
        require(preparationTime < _redemptionInterval);
        _preparationTime = preparationTime;
        emit PreparationTimeSet(preparationTime);
    }

    /**
     * @notice Set redemption token.
     *
     * @dev Current contract supports only stablecoins.
     *
     * @param token Address of the redemption token.
     */
    function setRedemptionToken(IERC20 token) external onlyOwner {
        require(token != IERC20(address(0)));
        _redemptionToken = token;
        emit RedemptionTokenSet(token);
    }

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
        external
        onlyOwner
    {
        require(redemptions.length == 0, "Redemptions are already active");
        require(
            _redemptionInterval > 0 &&
                _preparationTime > 0 &&
                _redemptionToken != IERC20(address(0))
        );
        _addNewRedemption(nextRedemptionExactTime, fee);
    }

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
        external
        onlyOwner
    {
        require(fee < 1001);
        uint256 redemptionsLength = redemptions.length;
        require(redemptionsLength > 0);
        uint256 index = redemptionsLength - 1;
        Redemption storage redemption = redemptions[index];
        require(
            block.timestamp > redemption.redemptionTime,
            "Redemption time in the future"
        );
        // get price + setprice time
        require(
            IManagedVault(address(vault)).setPriceBlockNumber() + 5001 >
                block.number,
            "Price not set within 5000 blocks"
        );
        uint256 price = IManagedVault(address(vault)).vaultPrice();
        // calculate fee
        uint256 feeAmount = (redemption.fee * price) / 10000;
        price -= feeAmount;
        uint256 amount = price * redemption.pending;
        // get amount
        (redemption.token).safeTransferFrom(msg.sender, address(this), amount);
        redemption.price = price;
        redemption.active = true;
        IManagedVault(address(vault)).burn(redemption.pending);
        emit RedemptionActivated(index, price, redemption.token);
        _addNewRedemption(nextRedemptionExactTime, fee);
    }

    /* ============ Internal Functions ============ */

    function _addNewRedemption(uint256 nextRedemptionExactTime, uint256 fee)
        internal
    {
        require(fee < 1001);
        uint256 redemptionTime;
        uint256 registrationEndTime;

        if (nextRedemptionExactTime > 0) {
            require(
                nextRedemptionExactTime - _preparationTime > block.timestamp,
                "Redemption time too close"
            );
            redemptionTime = nextRedemptionExactTime;
        } else {
            redemptionTime = block.timestamp + _redemptionInterval;
        }
        registrationEndTime = redemptionTime - _preparationTime;

        redemptions.push(
            Redemption(
                redemptionTime,
                registrationEndTime,
                0,
                0,
                fee,
                _redemptionToken,
                false
            )
        );
        emit NewRedemption(
            redemptions.length - 1,
            redemptionTime,
            registrationEndTime,
            fee,
            _redemptionToken
        );
    }

    /* ============ External Functions ============ */

    /**
     * @notice Reedem redemption tokens.
     *
     * @param claims List of redemption indexes to claim from.
     */
    function redeem(uint256[] memory claims) external {
        for (uint256 i = 0; i < claims.length; i++) {
            uint256 index = claims[i];
            Redemption storage redemption = redemptions[index];
            require(
                redemption.active == true &&
                    block.timestamp >= redemption.redemptionTime,
                "Redemption is not active yet"
            );
            uint256 amount = userClaims[msg.sender][index];
            require(amount > 0, "No tokens registered");
            userClaims[msg.sender][index] = 0;
            redemption.pending -= amount;
            amount *= redemption.price;
            (redemption.token).safeTransfer(msg.sender, amount);
            emit Reedemed(index, msg.sender, amount, redemption.token);
        }
    }

    /**
     * @notice Register vault tokens for the current redemption.
     *
     * @dev Only works if current redemtpion 'registrationTimeEnd' hasn't passed yet.
     *
     * @param amount Amount of vault tokens to register.
     */
    function register(uint256 amount) external {
        uint256 index = redemptions.length - 1;
        Redemption storage redemption = redemptions[index];
        require(
            block.timestamp <= redemption.registrationEndTime,
            "Registration time ended"
        );
        require(vault.balanceOf(msg.sender) >= amount, "Too few vault tokens");
        userClaims[msg.sender][index] += amount;
        redemption.pending += amount;
        vault.safeTransferFrom(msg.sender, address(this), amount);
        emit Registered(index, msg.sender, amount, redemption.token);
    }

    /**
     * @notice Unegister vault tokens for the current redemption.
     *
     * @dev Only works if current redemtpion 'registrationTimeEnd' hasn't passed yet.
     *
     * @param amount Amount of vault tokens to register.
     */
    function unregister(uint256 amount) external {
        uint256 index = redemptions.length - 1;
        Redemption storage redemption = redemptions[index];
        require(
            block.timestamp <= redemption.registrationEndTime,
            "Registration time ended"
        );
        require(
            userClaims[msg.sender][index] >= amount,
            "Too few registered tokens"
        );
        userClaims[msg.sender][index] -= amount;
        redemption.pending -= amount;
        vault.safeTransfer(msg.sender, amount);
        emit Unregistered(index, msg.sender, amount, redemption.token);
    }

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
        returns (uint256 amount, IERC20 token)
    {
        require(_redemptionIndex < redemptions.length);
        amount = userClaims[_user][_redemptionIndex];
        token = redemptions[_redemptionIndex].token;
    }

    /**
     * @notice Returns number of redemptions in the list.
     *
     * @return length Number of redemptions (length of redemptions list).
     */
    function getRedemptionsLength() external view returns (uint256 length) {
        return redemptions.length;
    }

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
        )
    {
        require(_redemptionIndex < redemptions.length);
        Redemption storage redemption = redemptions[_redemptionIndex];
        redemptionTime = redemption.redemptionTime;
        registrationEndTime = redemption.registrationEndTime;
        pending = redemption.pending;
        price = redemption.price;
        fee = redemption.fee;
        token = redemption.token;
        active = redemption.active;
    }

    /**
     * @notice Returns next redemption fee.
     *
     * @return nextRedemptionFee Next redemption fee.
     */
    function getNextRedemptionFee()
        external
        view
        returns (uint256 nextRedemptionFee)
    {
        uint256 length = redemptions.length;
        require(length > 0);
        nextRedemptionFee = redemptions[length - 1].fee;
    }

    /**
     * @notice Returns next redemption time.
     *
     * @return nextRedemptionTime Time after which redemption can be activated.
     */
    function getNextRedemptionTime()
        external
        view
        returns (uint256 nextRedemptionTime)
    {
        uint256 length = redemptions.length;
        require(length > 0);
        nextRedemptionTime = redemptions[length - 1].redemptionTime;
    }

    /**
     * @notice Returns if current redemption's registration period is open.
     *
     * @return registrationOpen If registration period is open.
     */
    function isRegistrationOpen()
        external
        view
        returns (bool registrationOpen)
    {
        uint256 length = redemptions.length;
        if (length == 0) return false;
        if (block.timestamp > redemptions[length - 1].registrationEndTime) {
            return false;
        } else {
            return true;
        }
    }
}
