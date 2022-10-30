// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @title Redemption
 * @author pbnather
 */

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IRedemptionHelper.sol";
import "./interfaces/IManagedVault.sol";

contract RedemptionHelper is IRedemptionHelper, Ownable {
    /* ============ Structures ============ */

    struct Redemption {
        uint256 redemptionTime;
        uint256 registrationEndTime;
        uint256 pending;
        uint256 price;
        IERC20 token;
        bool active;
    }

    /* ============ State Variables ============ */

    address public vault;
    Redemption[] public redemptions;
    mapping(address => mapping(uint256 => uint256)) public userClaims;

    uint256 private _preparationTime;
    uint256 private _redemptionInterval;
    IERC20 private _redemptionToken;

    /* ============ Initializer ============ */

    constructor() {
        vault = owner();
        redemptions.push(Redemption(0, 0, 0, 0, IERC20(address(0)), false));
    }

    /* ============ External Owner Functions ============ */

    function SetRedemptionInterval(uint256 interval) external onlyOwner {
        require(interval > _preparationTime);
        _redemptionInterval = interval;
    }

    function SetPreparationTime(uint256 preparationTime) external onlyOwner {
        require(preparationTime < _redemptionInterval);
        _preparationTime = preparationTime;
    }

    function SetRedemptionToken(IERC20 token) external onlyOwner {
        require(_redemptionToken != token);
        _redemptionToken = token;
    }

    function Initialize(uint256 nextRedemptionExactTime) external onlyOwner {
        require(
            redemptions[0].redemptionTime == 0,
            "Redemptions are already active"
        );
        require(
            _redemptionInterval > 0 &&
                _preparationTime > 0 &&
                _redemptionToken != IERC20(address(0))
        );
        redemptions[0].token = _redemptionToken;
        _initilaizeRedemptionTime(0, nextRedemptionExactTime);
    }

    function ActivateRedemption(uint256 nextRedemptionExactTime, uint256 fee)
        external
        onlyOwner
    {
        uint256 ridx = redemptions.length - 1;
        require(
            block.timestamp >= redemptions[ridx].redemptionTime &&
                redemptions[ridx].active == false,
            "Redemption already activated"
        );
        // get price + setprice time
        require(
            IManagedVault(vault).setPriceBlockNumber() + 5000 >= block.number,
            "Price not set within 5000 blocks"
        );
        uint256 price = IManagedVault(vault).vaultPrice();
        // calculate fee
        uint256 feeAmount = (fee * price) / 10000;
        price -= feeAmount;
        uint256 amount = price * redemptions[ridx].pending;
        // get amount
        (redemptions[ridx].token).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        redemptions[ridx].price = price;
        redemptions[ridx].active = true;
        // create new redemption
        redemptions.push(Redemption(0, 0, 0, 0, _redemptionToken, false));
        _initilaizeRedemptionTime(ridx + 1, nextRedemptionExactTime);
    }

    function _initilaizeRedemptionTime(
        uint256 index,
        uint256 nextRedemptionExactTime
    ) internal {
        if (nextRedemptionExactTime != 0) {
            require(
                nextRedemptionExactTime - _preparationTime > block.timestamp,
                "Redemption time too close"
            );
            redemptions[index].redemptionTime = nextRedemptionExactTime;
            redemptions[index].registrationEndTime =
                nextRedemptionExactTime -
                _preparationTime;
        } else {
            redemptions[index].redemptionTime =
                block.timestamp +
                _redemptionInterval;
            redemptions[index].registrationEndTime =
                redemptions[index].redemptionTime -
                _preparationTime;
        }
    }

    /* ============ External Functions ============ */

    function Redeem(uint256[] memory claims) external {
        for (uint256 i = 0; i < claims.length; i++) {
            uint256 ridx = claims[i];
            require(
                redemptions[ridx].active == true &&
                    block.timestamp >= redemptions[ridx].redemptionTime,
                "Redemption is not active yet"
            );
            require(userClaims[msg.sender][ridx] > 0, "No tokens registered");
            uint256 amount = userClaims[msg.sender][ridx];
            userClaims[msg.sender][ridx] = 0;
            redemptions[ridx].pending -= amount;
            amount *= redemptions[ridx].price;
            (redemptions[ridx].token).transferFrom(
                address(this),
                msg.sender,
                amount
            );
        }
    }

    function Register(uint256 amount) external {
        uint256 ridx = redemptions.length - 1;
        require(
            block.timestamp <= redemptions[ridx].registrationEndTime,
            "Registration time ended"
        );
        require(
            IERC20(vault).balanceOf(msg.sender) >= amount,
            "Too few vault tokens"
        );
        userClaims[msg.sender][ridx] += amount;
        redemptions[ridx].pending += amount;
        IERC20(vault).transferFrom(msg.sender, address(this), amount);
    }

    function Unregister(uint256 amount) external {
        uint256 ridx = redemptions.length - 1;
        require(
            block.timestamp <= redemptions[ridx].registrationEndTime,
            "Registration time ended"
        );
        require(
            userClaims[msg.sender][ridx] >= amount,
            "Too few registered tokens"
        );
        userClaims[msg.sender][ridx] -= amount;
        redemptions[ridx].pending -= amount;
        IERC20(vault).transferFrom(address(this), msg.sender, amount);
    }
}
