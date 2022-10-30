// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @title IManagedVault
 * @author Teragon
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IManagedVault {
    /* ============ Events ============ */

    /**
     * @notice Emitted when a user deposits the native cryptocurrency (Ether for the Ethereum network)
     *         into the contract.
     *
     * @param depositor The address of the user who deposited the native cryptocurrency.
     * @param amount The amount of native cryptocurrency deposited.
     */
    event DepositNative(address indexed depositor, uint256 indexed amount);

    /**
     * @notice Emitted when a user deposits a deposit token into the contract.
     */
    event DepositToken(
        IERC20 indexed tokenAddress,
        address indexed depositor,
        uint256 indexed amount
    );

    /**
     * @notice Emitted when the native cryptocurrency's (Ether for the Ethereum network)  state for deposits is changed.
     */
    event SetNativeDepositState(bool state);

    /**
     * @notice Emitted when a token is set or unset as one of the whitelisted deposit tokens.
     */
    event SetTokenDepositState(IERC20 tokenAddress, bool state);

    /**
     * @notice Emitted when the manager sets the vault price for a given block number.
     */
    event SetVaultPrice(uint256 indexed blockNumber, uint256 indexed price);

    /**
     * @notice Emitted when the manager sets the price of the native cryptocurrency of the network
     * (Ether for the Ethereum network) for the deposits.
     */
    event SetNativePrice(uint256 indexed blockNumber, uint256 indexed price);

    /**
     * @notice Emitted when the manager sets the price of a deposit token for the deposits.
     */
    event SetTokenPrice(
        uint256 indexed blockNumber,
        IERC20 indexed tokenAddress,
        uint256 indexed price
    );

    /**
     * @notice Emitted when the manager sets the minimum of amount native cryptocurrency of the network that can be deposited.
     */
    event SetNativeMinimumDepositAmount(uint256 indexed amount);

    /**
     * @notice Emitted when the manager sets minimum deposit amount for a deposit token.
     */
    event SetTokenMinimumDepositAmount(
        IERC20 indexed tokenAddress,
        uint256 indexed amount
    );

    /**
     * @notice Emitted when tokens are minted to depositors corresponding to their pending deposits.
     */
    event Minted(address indexed depositor, uint256 indexed amount);

    /**
     * @notice Emitted when the owner invokes an arbitrary function of any contract.
     */
    event Invoked(
        address indexed target,
        uint256 indexed value,
        bytes data,
        bytes returnValue
    );

    /* ============ External Functions ============ */

    /**
     * @notice Deposits an amount of the native cryptocurrency (Ether for the Ethereum network) into the managed vault.
     *
     * @dev msg.value must be equal to or greater than minimumDepositAmount.
     *      Requires that nativeDepositState is true.
     *      Emits a {DepositNative} event.
     */
    function depositNative() external payable;

    /**
     * @notice Deposits the given token amount into the managed vault.
     *
     * @dev Requires that the token address is whitelisted.
     *      Requires the amount to be allowed for transfer by this contract.
     *      Amount must be equal to or greater than minimumDepositTokenAmount.
     *      Emits a {DepositToken} event.
     *
     * @param tokenAddress The address of the token to deposit.
     * @param amount The amount of the token to deposit.
     */
    function depositToken(IERC20 tokenAddress, uint256 amount) external;

    /* ============ External Owner Functions ============ */

    /**
     * @notice Sets the native cryptocurrency (Ether for the Ethereum network) whitelist state.
     *
     * @dev {depositNative} function won't work unless this function is set to true.
     *      Emits a {SetNativeDepositState} event if whitelist state is changed for native cryptocurrency.
     *
     * @param state The new state of the whitelist.
     */
    function setNativeDepositState(bool state) external; //onlyOwner

    /**
     * @notice Sets deposit token whitelist state. Only whitelisted tokens are accepted for deposits.
     *
     * @dev If state is true, the token is allowed for deposits. Otherwise deposit function is reverted.
     *      Emits a {SetTokenDepositState} event if whitelist state is changed for the token.
     *
     * @param tokenAddress Address of the token.
     * @param state The new state of the whitelist.
     */
    function setTokenDepositState(IERC20 tokenAddress, bool state) external; //onlyOwner

    /**
     * @notice Sets the vault's token price, native price, and all token prices for a given blockNumber.
     *         Afterwards, the pending deposits up until the blockNumber can be minted.
     *
     * @dev The native price must be set regardless of its deposit status. The token prices should be set in the right order.
     *      Emits {SetVaultPrice}, {SetNativePrice}, and {SetTokenPrice} events when these values are updated.
     *
     * @param blockNumber The block number of the new prices. Must be lower than block.number
     * @param vaultPrice_ New price of the vault's token.
     * @param nativePrice_ New price of the native cryptocurrency(Ether for the Ethereum network).
     * @param tokenAddresses Array of token addresses that will have their prices set. The array must be in the right order.
     * @param tokenPrices_ Array of token prices.
     */
    function setPrices(
        uint256 blockNumber,
        uint256 vaultPrice_,
        uint256 nativePrice_,
        IERC20[] calldata tokenAddresses,
        uint256[] calldata tokenPrices_
    ) external; //onlyOwner

    /**
     * @notice Sets the minimum amount of native cryptocurrency that can be deposited.
     *
     * @dev Protection against dust attacks.
     *      Emits a {SetNativeMinimumDepositAmount} event.
     *
     * @param amount The minimum amount of native cryptocurrency that can be deposited.
     */
    function setNativeMinimumDepositAmount(uint256 amount) external; //onlyOwner

    /**
     * @notice Sets the minimum amount of a deposit token that can be deposited.
     *
     * @dev Protection against dust attacks.
     *      Emits a {SetTokenMinimumDepositAmount} event.
     *
     * @param tokenAddress          The address of the deposit token.
     * @param amount                The minimum amount of the deposit token that can be deposited.
     */
    function setTokenMinimumDepositAmount(IERC20 tokenAddress, uint256 amount)
        external; //onlyOwner

    /**
     * @notice Mints tokens for new deposits since the last mint until (including) the setPriceBlockNumber.
     *
     * @dev Removes the pending deposits, and adds corresponding amount of balances to depositors.
     *      Emits {Minted} events.
     *
     * @param maxMints      Maximum number of deposits that will be minted. To prevent exceeding block gas limit.
     *
     * @return mintCount    The number of mints performed.
     */
    function mint(uint256 maxMints) external returns (uint256 mintCount); //onlyOwner

    /**
     * @notice Low level function that allows a module to make an arbitrary function call to any contract.
     *
     * @dev Emits an {Invoked} event.
     *
     * @param target                 Address of the smart contract to call
     * @param value                  Quantity of Ether to provide the call (typically 0)
     * @param data                   Encoded function selector and arguments
     *
     * @return returnValue           Bytes encoded return value
     */
    function invoke(
        address target,
        bytes calldata data,
        uint256 value
    ) external returns (bytes memory returnValue); //onlyOwner

    /* ============ External View Functions ============ */

    function setPriceBlockNumber()
        external
        view
        returns (uint256 setPriceBlockNumber);

    function vaultPrice() external view returns (uint256 vaultPrice);

    /**
     * @notice Returns the token addresses available for deposits.
     *
     * @return tokenAddresses Array of token addresses that is available for deposits.
     */
    function tokenAdresses()
        external
        view
        returns (address[] memory tokenAddresses);

    /**
     * @notice Returns the number of pending mints and the total number of vault tokens to be minted.
     *
     * @dev Only considers the blocks at or before setPriceBlockNumber.
     *      The response of this function could be used to simulate the response of the mint function.
     *
     * @param maxMints  The maximum number of mints to be simulated.
     *
     * @return count    The number of pending mints.
     * @return amount   The number of vault tokens to be minted.
     */
    function pendingMintsCountAndAmount(uint256 maxMints)
        external
        view
        returns (uint256 count, uint256 amount);

    /**
     * @notice Returns the remaining number of native cryptocurrency (Ether for the Ethereum network) deposits amount for a given depositor.
     *
     * @param depositor     The address of the depositor.
     *
     * @return totalAmount  Remaining native cryptocurrency deposited by depositor.
     */
    function pendingNativeDepositAmount(address depositor)
        external
        view
        returns (uint256 totalAmount);

    /**
     * @notice Returns the remaining number of deposit amount for the given token address and depositor.
     *
     * @param depositor     The address of the depositor.
     * @param tokenAddress  The address of the deposit token.
     *
     * @return totalAmount  Remaining deposit amount for the given token address and depositor.
     */
    function pendingTokenDepositAmount(address depositor, IERC20 tokenAddress)
        external
        view
        returns (uint256 totalAmount);

    /**
     * @notice Returns the total remaining deposit amount for the native cryptocurrency (Ether for the Ethereum network) up to a block number.
     *
     * @param maxBlockNumber    The maximum block number to make the calculations for.
     *
     * @return totalAmount      Remaining native cryptocurrency deposited up to the given block number.
     */
    function totalPendingNativeDepositAmount(uint256 maxBlockNumber)
        external
        view
        returns (uint256 totalAmount);

    /**
     * @notice Returns the total remaining deposit amount for the given token address up to (including) a block number.
     *
     * @param maxBlockNumber    The maximum block number to make the calculations for.
     * @param tokenAddress      The address of the deposit token.
     *
     * @return totalAmount      Remaining deposit amount for the given token address up to (including) the given block number.
     */
    function totalPendingTokenDepositAmount(
        uint256 maxBlockNumber,
        IERC20 tokenAddress
    ) external view returns (uint256 totalAmount);
}
