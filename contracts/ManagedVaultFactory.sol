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

    function createVault(
        address _manager,
        string memory _tokenName,
        string memory _tokenSymbol
    ) external onlyOwner returns (address) {
        address owner = owner();
        address helper = Clones.clone(redemptionHelperImpl);
        address vault = Clones.clone(managedVaultImpl);
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
        emit VaultCreated(vault, _manager, _tokenName, _tokenSymbol);
        return vault;
    }

    function changeManagedVaultImpl(address _impl) external onlyOwner {
        require(_impl != address(0));
        address oldImpl = managedVaultImpl;
        managedVaultImpl = _impl;
        emit ManagedVaultImplChanged(oldImpl, _impl);
    }

    function changeRedemptionHelperImpl(address _impl) external onlyOwner {
        require(_impl != address(0));
        address oldImpl = redemptionHelperImpl;
        redemptionHelperImpl = _impl;
        emit RedemptionHelperImplChanged(oldImpl, _impl);
    }

    function changeState(address _vault, bool _active) external {
        Info storage vaultInfo = info[_vault];
        require(vaultInfo.exists);
        require(vaultInfo.active != _active);
        vaultInfo.active = _active;
        emit StateChanged(_vault, _active);
    }

    /* ============ External View Functions ============ */

    function getVaults() external view returns (address[] memory) {
        return vaults;
    }

    function getActiveVaults() external view returns (address[] memory) {
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

    function vaultExists(address _vault) external view returns (bool) {
        return info[_vault].exists;
    }

    function vaultActive(address _vault) external view returns (bool) {
        return info[_vault].exists;
    }
}
