// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @title ManagedVault
 * @author Teragon, pbnather
 *
 * @notice A flexible vault for tracking deposits and minting corresponding vault tokens to the depositors.
 *         The deposits are transferred to the owner and the owner is able to manage the funds without any restrictions.
 *
 *                                                =
 *                                             ==== ===
 *                                           ======= =======
 *                       == ==           =========== =======
 *                    ===== ======    ============== =======
 *                 ======== =========   ============ =======
 *             ============ ============   ========= =======
 *          ===============   =============  ======= =======
 *       =============== ======= ==========  ======= =======
 *   =============== ============== =======  ======= =======
 *  ============= ====================  ===  ======= =======
 *  ========= ============================   ======= =======
 *  ====== ==============     ============  ======== =======
 *  == ==============   ===  ===  ====  ============ =======
 *   ============== =======  ======  ==============   ======
 *      =========== =======  ======= ===========  ====== ===
 *          ======= =======  ======= =======  =============
 *             ==== =======  ======= ====  ==============
 *                  =======  =======    ==============
 *                  =======  =======  ==============
 *                  =======  ===========  =====  ===
 *                  =======  ==============  =======
 *                  ===  =====  ====================
 *                    ============ =================
 *                    ===============  =============
 *                        =============== ==========
 *                           ===============  ======
 *                               ==============  ===
 *                                  ==============
 *                                      ========
 *                                         ==
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "./interfaces/IManagedVault.sol";
import "./libraries/PendingDeposit.sol";

/* ============ Errors ============ */

/// @notice The owner must do the precise calculations of the prices at a specific block in the past.
/// @param blockNumber The given block number that is equal or larger than the current block.
error BlockNumberInTheFuture(uint256 blockNumber);

/// @notice Thrown when a token address is not as expected. In setPrices, the token address array must be
///         exactly as the response of the tokenAdresses() function.
/// @param givenTokenAddress The given token address.
/// @param expectedTokenAddress The expected token address.
error InvalidTokenAddress(
    IERC20 givenTokenAddress,
    IERC20 expectedTokenAddress
);

/// @notice Thrown when the deposit is not allowed for the native cryptocurrency or the token
error DepositNotAllowed();

/// @notice Thrown when the deposit amount is less than the minimum amount
/// @param amount The amount to be deposited
/// @param minimumAmount The minimum amount for such deposits
error AmountTooLittle(uint256 amount, uint256 minimumAmount);

/// @notice Thrown when a required transfer is failed
error TransferFailed();

/* ============ Contract ============ */

// TODO: Remove upgradeability
contract ManagedVault is
    Initializable,
    OwnableUpgradeable,
    ERC20Upgradeable,
    IManagedVault
{
    /* ============ Libraries ============ */

    using AddressUpgradeable for address;
    using EnumerableSet for EnumerableSet.AddressSet;
    using PendingDeposit for PendingDeposit.Queue;

    /* ============ State Variables ============ */

    // Pending deposits for the native cryptocurrency (Ether for the Ethereum network)
    PendingDeposit.Queue pendingNativeDeposits;
    // A mapping from deposit token address to pending token deposits for these tokens
    mapping(IERC20 => PendingDeposit.Queue) public pendingTokenDeposits;

    // The price of 1e18 of this contract's token in USD (Display the pros and cons of using a token such as USDC in the future)
    uint256 public vaultPrice;

    // The block number of the last setPrice function call
    uint256 public setPriceBlockNumber;

    // For the native cryptocurrency (Ether for the Ethereum network)
    bool public nativeDepositState;
    uint256 public nativePrice;
    uint256 public nativeMinimumDepositAmount;

    // For Tokens
    EnumerableSet.AddressSet private tokenDepositStates;
    mapping(IERC20 => uint256) public tokenPrices;
    mapping(IERC20 => uint256) public tokenMinimumDepositAmounts;

    /* ============ Initializer ============ */
    function initialize(
        address owner_,
        string memory name_,
        string memory symbol_
    ) external initializer {
        __ERC20_init(name_, symbol_);
        __Ownable_init();
        _transferOwnership(owner_);
    }

    /* ============ External Owner Functions ============ */

    /**
     * @notice Sets the native cryptocurrency (Ether for the Ethereum network) whitelist state.
     *
     * @dev {depositNative} function won't work unless this function is set to true.
     *      Emits a {SetNativeDepositState} event if whitelist state is changed for native cryptocurrency.
     *
     * @param state The new state of the whitelist.
     */
    function setNativeDepositState(bool state) external onlyOwner {
        require(nativeDepositState != state);

        nativeDepositState = state;

        emit SetNativeDepositState(state);
    }

    /**
     * @notice Sets deposit token whitelist state. Only whitelisted tokens are accepted for deposits.
     *
     * @dev If state is true, the token is allowed for deposits. Otherwise deposit function is reverted.
     *      Emits a {SetTokenDepositState} event if whitelist state is changed for the token.
     *
     * @param tokenAddress Address of the token.
     * @param state The new state of the whitelist.
     */
    function setTokenDepositState(IERC20 tokenAddress, bool state)
        external
        onlyOwner
    {
        require(tokenDepositStates.contains(address(tokenAddress)) != state);

        if (state) {
            tokenDepositStates.add(address(tokenAddress));
        } else {
            tokenDepositStates.remove(address(tokenAddress));
        }

        emit SetTokenDepositState(tokenAddress, state);
    }

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
    ) external onlyOwner {
        // Set the block number
        if (blockNumber >= block.number) {
            revert BlockNumberInTheFuture({blockNumber: blockNumber});
        }
        setPriceBlockNumber = blockNumber;

        // Set the vault price
        if (vaultPrice != vaultPrice_) {
            vaultPrice = vaultPrice_;
            emit SetVaultPrice(blockNumber, vaultPrice);
        }

        // Set the native price
        if (nativePrice != nativePrice_) {
            nativePrice = nativePrice_;
            emit SetNativePrice(blockNumber, nativePrice);
        }

        // Set the token prices
        uint256 tokensCount = tokenDepositStates.length();
        for (uint256 tokenIndex = 0; tokenIndex < tokensCount; ) {
            IERC20 depositTokenAddress = IERC20(
                tokenDepositStates.at(tokenIndex)
            );
            // Perform the check that the token addresses are in the exact order step by step
            if (depositTokenAddress != tokenAddresses[tokenIndex]) {
                revert InvalidTokenAddress({
                    givenTokenAddress: tokenAddresses[tokenIndex],
                    expectedTokenAddress: depositTokenAddress
                });
            }

            if (tokenPrices[depositTokenAddress] != tokenPrices_[tokenIndex]) {
                tokenPrices[depositTokenAddress] = tokenPrices_[tokenIndex];
                emit SetTokenPrice(
                    blockNumber,
                    depositTokenAddress,
                    tokenPrices[depositTokenAddress]
                );
            }
            // TODO: check unchecked
            unchecked {
                tokenIndex++;
            }
        }
    }

    /**
     * @notice Sets the minimum amount of native cryptocurrency that can be deposited.
     *
     * @dev Protection against dust attacks.
     *      Emits a {SetNativeMinimumDepositAmount} event.
     *
     * @param amount The minimum amount of native cryptocurrency that can be deposited.
     */
    function setNativeMinimumDepositAmount(uint256 amount) external onlyOwner {
        require(nativeMinimumDepositAmount != amount);

        nativeMinimumDepositAmount = amount;

        emit SetNativeMinimumDepositAmount(amount);
    }

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
        external
        onlyOwner
    {
        require(tokenMinimumDepositAmounts[tokenAddress] != amount);

        tokenMinimumDepositAmounts[tokenAddress] = amount;

        emit SetTokenMinimumDepositAmount(tokenAddress, amount);
    }

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
    function mint(uint256 maxMints)
        external
        onlyOwner
        returns (uint256 mintCount)
    {
        // Put storage variables on stack to avoid SLOAD operations in loops
        uint256 stackSetPriceBlockNumber = setPriceBlockNumber;
        uint256 stackVaultPrice = vaultPrice;

        // Minting for the native cryptocurrency (Ether for the Ethereum Network)
        uint256 stackNativePrice = nativePrice;
        uint256 remainingPendingNativeDeposits = pendingNativeDeposits.length();
        if (nativeDepositState) {
            while (0 < remainingPendingNativeDeposits && mintCount < maxMints) {
                PendingDeposit.Item
                    memory nextPendingDeposit = pendingNativeDeposits.peek();
                if (nextPendingDeposit.blockNumber > setPriceBlockNumber) {
                    break;
                }

                pendingNativeDeposits.dequeue();
                unchecked {
                    remainingPendingNativeDeposits--;
                }

                uint256 vaultTokenAmount = (nextPendingDeposit.amount *
                    stackNativePrice) / stackVaultPrice;
                _mint(nextPendingDeposit.depositor, vaultTokenAmount);
                unchecked {
                    mintCount++;
                }

                emit Minted(nextPendingDeposit.depositor, vaultTokenAmount);
            }
        }

        // Minting for the deposit tokens
        uint256 tokensCount = tokenDepositStates.length();
        for (uint256 tokenIndex = 0; tokenIndex < tokensCount; ) {
            IERC20 depositTokenAddress = IERC20(
                tokenDepositStates.at(tokenIndex)
            );
            uint256 stackTokenPrice = tokenPrices[depositTokenAddress];
            uint256 remainingPendingTokenDeposits = pendingTokenDeposits[
                depositTokenAddress
            ].length();
            while (0 < remainingPendingTokenDeposits && mintCount < maxMints) {
                PendingDeposit.Item
                    memory nextPendingDeposit = pendingTokenDeposits[
                        depositTokenAddress
                    ].peek();
                if (nextPendingDeposit.blockNumber > stackSetPriceBlockNumber) {
                    break;
                }

                pendingTokenDeposits[depositTokenAddress].dequeue();
                unchecked {
                    remainingPendingTokenDeposits--;
                }

                uint256 vaultTokenAmount = (nextPendingDeposit.amount *
                    stackTokenPrice) / stackVaultPrice;
                _mint(nextPendingDeposit.depositor, vaultTokenAmount);
                unchecked {
                    mintCount++;
                }

                emit Minted(nextPendingDeposit.depositor, vaultTokenAmount);
            }

            unchecked {
                tokenIndex++;
            }
        }
    }

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
    ) external onlyOwner returns (bytes memory returnValue) {
        returnValue = target.functionCallWithValue(data, value);
        emit Invoked(target, value, data, returnValue);
    }

    /* ============ External Functions ============ */

    /**
     * @notice Deposits an amount of the native cryptocurrency (Ether for the Ethereum network) into the managed vault.
     *
     * @dev msg.value must be equal to or greater than minimumDepositAmount.
     *      Requires that nativeDepositState is true.
     *      Emits a {DepositNative} event.
     */
    function depositNative() external payable {
        address depositor = msg.sender;
        uint256 amount = msg.value;

        if (!nativeDepositState) {
            revert DepositNotAllowed();
        }

        if (amount < nativeMinimumDepositAmount) {
            revert AmountTooLittle({
                amount: amount,
                minimumAmount: nativeMinimumDepositAmount
            });
        }

        (bool success, ) = payable(owner()).call{value: msg.value}("");
        if (!success) {
            revert TransferFailed();
        }

        PendingDeposit.Item memory pendingDeposit = PendingDeposit.Item({
            blockNumber: block.number,
            depositor: depositor,
            amount: amount
        });

        pendingNativeDeposits.enqueue(pendingDeposit);
        emit DepositNative(depositor, amount);
    }

    /**
     * @notice Deposits the given token amount into the managed vault.
     *
     * @dev Requires that the token address is whitelisted.
     *      Requires the amount to be allowed for transfer by this contract.
     *      Amount must be equal to or greater than minimumDepositTokenAmount.
     *      Emits a {DepositToken} event.
     *
     * @param tokenAddress  The address of the token to deposit.
     * @param amount        The amount of the token to deposit.
     */
    function depositToken(IERC20 tokenAddress, uint256 amount) external {
        address depositor = msg.sender;

        if (!tokenDepositStates.contains(address(tokenAddress))) {
            revert DepositNotAllowed();
        }

        if (amount < tokenMinimumDepositAmounts[tokenAddress]) {
            revert AmountTooLittle({
                amount: amount,
                minimumAmount: tokenMinimumDepositAmounts[tokenAddress]
            });
        }

        bool success = tokenAddress.transferFrom(depositor, owner(), amount);
        if (!success) {
            revert TransferFailed();
        }

        PendingDeposit.Item memory pendingDeposit = PendingDeposit.Item({
            blockNumber: block.number,
            depositor: depositor,
            amount: amount
        });

        pendingTokenDeposits[tokenAddress].enqueue(pendingDeposit);

        emit DepositToken(tokenAddress, depositor, amount);
    }

    /* ============ External View Functions ============ */

    /**
     * @notice Returns the token addresses available for deposits.
     *
     * @return tokenAddresses Array of token addresses that is available for deposits.
     */
    function tokenAdresses()
        external
        view
        returns (address[] memory tokenAddresses)
    {
        return tokenDepositStates.values();
    }

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
        returns (uint256 count, uint256 amount)
    {
        if (maxMints == 0) {
            return (count, amount);
        }

        if (nativeDepositState) {
            for (uint256 i = 0; i < pendingNativeDeposits.length(); i++) {
                if (count == maxMints) {
                    return (count, amount);
                }

                PendingDeposit.Item
                    memory pendingDeposit = pendingNativeDeposits.peekIndex(i);
                if (pendingDeposit.blockNumber > setPriceBlockNumber) {
                    break;
                }
                count++;
                amount += (pendingDeposit.amount * nativePrice) / vaultPrice;
            }
        }

        for (uint256 i = 0; i < tokenDepositStates.length(); i++) {
            IERC20 depositTokenAddress = IERC20(tokenDepositStates.at(i));
            uint256 tokenPrice = tokenPrices[depositTokenAddress];

            for (
                uint256 j = 0;
                j < pendingTokenDeposits[depositTokenAddress].length();
                j++
            ) {
                if (count == maxMints) {
                    return (count, amount);
                }

                PendingDeposit.Item
                    memory pendingDeposit = pendingTokenDeposits[
                        depositTokenAddress
                    ].peekIndex(j);
                if (pendingDeposit.blockNumber > setPriceBlockNumber) {
                    break;
                }
                count++;
                amount += (pendingDeposit.amount * tokenPrice) / vaultPrice;
            }
        }
    }

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
        returns (uint256 totalAmount)
    {
        for (uint256 i = 0; i < pendingNativeDeposits.length(); i++) {
            PendingDeposit.Item memory pendingDeposit = pendingNativeDeposits
                .peekIndex(i);
            if (pendingDeposit.depositor == depositor) {
                totalAmount += pendingDeposit.amount;
            }
        }
    }

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
        returns (uint256 totalAmount)
    {
        for (
            uint256 i = 0;
            i < pendingTokenDeposits[tokenAddress].length();
            i++
        ) {
            PendingDeposit.Item memory pendingDeposit = pendingTokenDeposits[
                tokenAddress
            ].peekIndex(i);
            if (pendingDeposit.depositor == depositor) {
                totalAmount += pendingDeposit.amount;
            }
        }
    }

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
        returns (uint256 totalAmount)
    {
        for (uint256 i = 0; i < pendingNativeDeposits.length(); i++) {
            PendingDeposit.Item memory pendingDeposit = pendingNativeDeposits
                .peekIndex(i);
            if (pendingDeposit.blockNumber > maxBlockNumber) {
                break;
            }
            totalAmount += pendingDeposit.amount;
        }
    }

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
    ) external view returns (uint256 totalAmount) {
        for (
            uint256 i = 0;
            i < pendingTokenDeposits[tokenAddress].length();
            i++
        ) {
            PendingDeposit.Item memory pendingDeposit = pendingTokenDeposits[
                tokenAddress
            ].peekIndex(i);
            if (pendingDeposit.blockNumber > maxBlockNumber) {
                break;
            }
            totalAmount += pendingDeposit.amount;
        }
    }
}
