// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @title ManagedVaultFactory
 * @author pbnather
 *
 * @notice Factory contract that allows creating new managed vaults.
 */

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "./interfaces/IManagedVault.sol";
import "./interfaces/IManagedVaultFactory.sol";
import "./interfaces/IRedemptionHelper.sol";

contract ManagedVaultFactory is IManagedVaultFactory, Ownable {
    /* ============ Structures ============ */

    struct Info {
        bool exists;
        bool active;
    }

    /* ============ State Variables ============ */

    address public managedVaultImpl;
    address public redemptionHelperImpl;

    address[] public vaults;
    mapping(address => Info) public info;

    /* ============ Constructor ============ */

    constructor(address _managedVaultImpl, address _redemptionHelperImpl) {
        require(_managedVaultImpl != address(0));
        require(_redemptionHelperImpl != address(0));
        managedVaultImpl = _managedVaultImpl;
        redemptionHelperImpl = _redemptionHelperImpl;
    }

    /* ============ External Owner Functions ============ */

    /**
     * @notice Creates new ManagedVault Clone, and RedemptionHelper Clone.
     *
     * @param _manager Vault manager.
     * @param _tokenName Name of the vault token.
     * @param _tokenSymbol Sumbol of the vault token.
     *
     * @return vault Address of the new ManagedVault.
     * @return helper Address of the new RedemptionHelper.
     */
    function createVault(
        address _manager,
        string memory _tokenName,
        string memory _tokenSymbol
    ) external onlyOwner returns (address vault, address helper) {
        address owner = owner();
        helper = Clones.clone(redemptionHelperImpl);
        vault = Clones.clone(managedVaultImpl);
        IRedemptionHelper(helper).initialize(_manager, owner);
        IManagedVault(vault).initialize(
            _manager,
            owner,
            helper,
            _tokenName,
            _tokenSymbol
        );
        vaults.push(vault);
        info[vault] = Info(true, false);
        emit VaultCreated(vault, helper, _manager, _tokenName, _tokenSymbol);
    }

    /**
     * @notice Change ManagedVault implementation address.
     *
     * @param _impl New implementation address.
     */
    function changeManagedVaultImpl(address _impl) external onlyOwner {
        require(_impl != address(0));
        address oldImpl = managedVaultImpl;
        managedVaultImpl = _impl;
        emit ManagedVaultImplChanged(oldImpl, _impl);
    }

    /**
     * @dev Change RedemptionHelper implementation address.
     *
     * @param _impl New implementation address.
     */
    function changeRedemptionHelperImpl(address _impl) external onlyOwner {
        require(_impl != address(0));
        address oldImpl = redemptionHelperImpl;
        redemptionHelperImpl = _impl;
        emit RedemptionHelperImplChanged(oldImpl, _impl);
    }

    /**
     * @notice Change vault's state (active or inactive).
     *
     * @dev This state is usefull only for frontend filtering.
     *
     * @param _vault Vault address.
     * @param _active New vault state.
     */
    function changeState(address _vault, bool _active) external onlyOwner {
        Info storage vaultInfo = info[_vault];
        require(vaultInfo.exists);
        require(vaultInfo.active != _active);
        vaultInfo.active = _active;
        emit StateChanged(_vault, _active);
    }

    /* ============ External View Functions ============ */

    /**
     * @notice Returns all vault addresses.
     *
     * @return allVaults Array of all vault addresses.
     */
    function getVaults() external view returns (address[] memory allVaults) {
        return vaults;
    }

    /**
     * @notice Returns all active vault addresses.
     *
     * @return allActiveVaults Array of all active vault addresses.
     */
    function getActiveVaults()
        external
        view
        returns (address[] memory allActiveVaults)
    {
        uint256 length = vaults.length;
        address[] memory tmpVaults = new address[](length);
        uint256 j = 0;
        for (uint256 i = 0; i < length; i++) {
            address vault = vaults[i];
            if (info[vault].active) {
                tmpVaults[j] = vault;
                j++;
            }
        }
        address[] memory activeVaults = new address[](j);
        for (uint256 i = 0; i < j; i++) {
            activeVaults[i] = tmpVaults[i];
        }
        return activeVaults;
    }

    /**
     * @notice Returns if vault exists.
     *
     * @param _vault Address of the vault.
     *
     * @return exists Boolean of the vault existance.
     */
    function vaultExists(address _vault) external view returns (bool exists) {
        return info[_vault].exists;
    }

    /**
     * @notice Returns if vault is active.
     *
     * @param _vault Address of the vault.
     *
     * @return isActive Boolean of the vault active status.
     */
    function vaultActive(address _vault) external view returns (bool isActive) {
        return info[_vault].active;
    }
}
