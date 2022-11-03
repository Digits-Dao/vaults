// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @title IManagedVaultFactory
 * @author pbnather
 */

interface IManagedVaultFactory {
    /* ============ Events ============ */

    event VaultCreated(
        address indexed vault,
        address indexed manager,
        string tokenName,
        string tokenSymbol
    );

    event ManagedVaultImplChanged(
        address indexed oldImpl,
        address indexed newImpl
    );

    event RedemptionHelperImplChanged(
        address indexed oldImpl,
        address indexed newImpl
    );

    event StateChanged(address indexed vault, bool active);

    /* ============ External Owner Functions ============ */

    function createVault(
        address _manager,
        string memory _tokenName,
        string memory _tokenSymbol
    ) external returns (address);

    function changeManagedVaultImpl(address _impl) external;

    function changeRedemptionHelperImpl(address _impl) external;

    function changeState(address _vault, bool _active) external;

    /* ============ External View Functions ============ */

    function getVaults() external view returns (address[] memory);

    function getActiveVaults() external view returns (address[] memory);

    function vaultExists(address _vault) external view returns (bool);

    function vaultActive(address _vault) external view returns (bool);
}
