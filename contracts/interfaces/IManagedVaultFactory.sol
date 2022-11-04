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

    /**
     * @notice Creates new ManagedVault Clone, and RedemptionHelper Clone.
     *
     * @param _manager Vault manager.
     * @param _tokenName Name of the vault token.
     * @param _tokenSymbol Sumbol of the vault token.
     */
    function createVault(
        address _manager,
        string memory _tokenName,
        string memory _tokenSymbol
    ) external returns (address); // onlyOwner

    /**
     * @notice Change ManagedVault implementation address.
     *
     * @param _impl New implementation address.
     */
    function changeManagedVaultImpl(address _impl) external; // onlyOwner

    /**
     * @notice Change RedemptionHelper implementation address.
     *
     * @param _impl New implementation address.
     */
    function changeRedemptionHelperImpl(address _impl) external; // onlyOwner

    /**
     * @notice Change vault's state (active or inactive).
     *
     * @dev This state is usefull only for frontend filtering.
     *
     * @param _vault Vault address.
     * @param _active New vault state.
     */
    function changeState(address _vault, bool _active) external; // onlyOwner

    /* ============ External View Functions ============ */

    /**
     * @notice Returns all vault addresses.
     *
     * @return allVaults Array of all vault addresses.
     */
    function getVaults() external view returns (address[] memory);

    /**
     * @notice Returns all active vault addresses.
     *
     * @return allActiveVaults Array of all active vault addresses.
     */
    function getActiveVaults() external view returns (address[] memory);

    /**
     * @notice Returns if vault exists.
     *
     * @param _vault Address of the vault.
     *
     * @return exists Boolean of the vault existance.
     */
    function vaultExists(address _vault) external view returns (bool);

    /**
     * @notice Returns if vault is active.
     *
     * @param _vault Address of the vault.
     *
     * @return isActive Boolean of the vault active status.
     */
    function vaultActive(address _vault) external view returns (bool);
}
