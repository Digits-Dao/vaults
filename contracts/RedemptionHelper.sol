// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @title RedemptionHelper
 * @author pbnather
 */

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "./interfaces/IRedemptionHelper.sol";
import "./interfaces/IManagedVault.sol";

contract RedemptionHelper is IRedemptionHelper, Ownable, Initializable {
    /* ============ Structures ============ */

    struct Redemption {
        uint256 redemptionTime;
        uint256 registrationEndTime;
        uint256 pending;
        uint256 price;
        uint256 fee;
        IERC20 token;
        bool active;
    }

    /* ============ State Variables ============ */

    Redemption[] public redemptions;
    mapping(address => mapping(uint256 => uint256)) public userClaims;

    address public admin;
    uint256 private _preparationTime;
    uint256 private _redemptionInterval;
    IERC20 private _redemptionToken;

    /* ============ Initializer ============ */

    function initialize(address owner_, address admin_) external initializer {
        require(owner_ != address(0));
        require(admin_ != address(0));
        _transferOwnership(owner_);
        admin = admin_;
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

    function setRedemptionInterval(uint256 interval) external onlyOwner {
        require(interval > _preparationTime);
        _redemptionInterval = interval;
        emit RedemptionIntervalSet(interval);
    }

    function setPreparationTime(uint256 preparationTime) external onlyOwner {
        require(preparationTime < _redemptionInterval);
        _preparationTime = preparationTime;
        emit PreparationTimeSet(preparationTime);
    }

    function setRedemptionToken(IERC20 token) external onlyOwner {
        require(token != IERC20(address(0)));
        _redemptionToken = token;
        emit RedemptionTokenSet(token);
    }

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
            block.timestamp > redemption.redemptionTime &&
                redemption.active == false,
            "Redemption already activated"
        );
        // get price + setprice time
        require(
            IManagedVault(owner()).setPriceBlockNumber() + 5001 > block.number,
            "Price not set within 5000 blocks"
        );
        uint256 price = IManagedVault(owner()).vaultPrice();
        // calculate fee
        uint256 feeAmount = (redemption.fee * price) / 10000;
        price -= feeAmount;
        uint256 amount = price * redemption.pending;
        // get amount
        (redemption.token).transferFrom(msg.sender, address(this), amount);
        redemption.price = price;
        redemption.active = true;
        IManagedVault(owner()).burn(redemption.pending);
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
            (redemption.token).transfer(msg.sender, amount);
            emit Reedemed(index, msg.sender, amount, redemption.token);
        }
    }

    function register(uint256 amount) external {
        uint256 index = redemptions.length - 1;
        Redemption storage redemption = redemptions[index];
        require(
            block.timestamp <= redemption.registrationEndTime,
            "Registration time ended"
        );
        require(
            IERC20(owner()).balanceOf(msg.sender) >= amount,
            "Too few vault tokens"
        );
        userClaims[msg.sender][index] += amount;
        redemption.pending += amount;
        IERC20(owner()).transferFrom(msg.sender, address(this), amount);
        emit Registered(index, msg.sender, amount, redemption.token);
    }

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
        IERC20(owner()).transfer(msg.sender, amount);
        emit Unregistered(index, msg.sender, amount, redemption.token);
    }

    /* ============ External View Functions ============ */
}
