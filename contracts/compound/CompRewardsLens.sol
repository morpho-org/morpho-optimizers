// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/ICompRewardsLens.sol";
import "./interfaces/IRewardsManager.sol";
import "./interfaces/IMorpho.sol";

import "./libraries/CompoundMath.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title RewardsManager.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice This contract exposes getters retrieving information about COMP rewards accrued through Morpho.
contract CompRewardsLens is ICompRewardsLens {
    using CompoundMath for uint256;

    /// STORAGE ///

    IMorpho public immutable morpho;
    IComptroller public immutable comptroller;
    IRewardsManager public immutable rewardsManager;

    /// ERRORS ///

    /// @notice Thrown when an invalid cToken address is passed to accrue rewards.
    error InvalidCToken();

    /// CONSTRUCTOR ///

    /// @notice Constructs the RewardsManager contract.
    /// @param _morpho The `morpho`.
    constructor(address _morpho) {
        morpho = IMorpho(_morpho);
        comptroller = IComptroller(morpho.comptroller());
        rewardsManager = IRewardsManager(morpho.rewardsManager());
    }

    /// EXTERNAL ///

    /// @notice Returns the unclaimed COMP rewards for the given cToken addresses.
    /// @param _cTokenAddresses The cToken addresses for which to compute the rewards.
    /// @param _user The address of the user.
    function getUserUnclaimedRewards(address[] calldata _cTokenAddresses, address _user)
        external
        view
        returns (uint256 unclaimedRewards)
    {
        unclaimedRewards = rewardsManager.userUnclaimedCompRewards(_user);

        for (uint256 i; i < _cTokenAddresses.length; ) {
            address cTokenAddress = _cTokenAddresses[i];

            (bool isListed, , ) = comptroller.markets(cTokenAddress);
            if (!isListed) revert InvalidCToken();

            unclaimedRewards += getAccruedSupplierComp(
                _user,
                cTokenAddress,
                morpho.supplyBalanceInOf(cTokenAddress, _user).onPool
            );
            unclaimedRewards += getAccruedBorrowerComp(
                _user,
                cTokenAddress,
                morpho.borrowBalanceInOf(cTokenAddress, _user).onPool
            );

            unchecked {
                ++i;
            }
        }
    }

    /// PUBLIC ///

    /// @notice Returns the accrued COMP rewards of a user since the last update.
    /// @param _supplier The address of the supplier.
    /// @param _cTokenAddress The cToken address.
    /// @param _balance The user balance of tokens in the distribution.
    /// @return The accrued COMP rewards.
    function getAccruedSupplierComp(
        address _supplier,
        address _cTokenAddress,
        uint256 _balance
    ) public view returns (uint256) {
        uint256 supplyIndex = getUpdatedSupplyIndex(_cTokenAddress);
        uint256 supplierIndex = rewardsManager.compSupplierIndex(_cTokenAddress, _supplier);

        if (supplierIndex == 0) return 0;
        return (_balance * (supplyIndex - supplierIndex)) / 1e36;
    }

    /// @notice Returns the accrued COMP rewards of a user since the last update.
    /// @param _borrower The address of the borrower.
    /// @param _cTokenAddress The cToken address.
    /// @param _balance The user balance of tokens in the distribution.
    /// @return The accrued COMP rewards.
    function getAccruedBorrowerComp(
        address _borrower,
        address _cTokenAddress,
        uint256 _balance
    ) public view returns (uint256) {
        uint256 borrowIndex = getUpdatedBorrowIndex(_cTokenAddress);
        uint256 borrowerIndex = rewardsManager.compBorrowerIndex(_cTokenAddress, _borrower);

        if (borrowerIndex == 0) return 0;
        return (_balance * (borrowIndex - borrowerIndex)) / 1e36;
    }

    /// @notice Returns the updated COMP supply index.
    /// @param _cTokenAddress The cToken address.
    /// @return The updated COMP supply index.
    function getUpdatedSupplyIndex(address _cTokenAddress) public view returns (uint256) {
        IComptroller.CompMarketState memory localSupplyState = rewardsManager
        .getLocalCompSupplyState(_cTokenAddress);
        uint256 blockNumber = block.number;

        if (localSupplyState.block == blockNumber) return localSupplyState.index;
        else {
            IComptroller.CompMarketState memory supplyState = comptroller.compSupplyState(
                _cTokenAddress
            );

            if (supplyState.block == blockNumber) return supplyState.index;
            else {
                uint256 deltaBlocks = blockNumber - supplyState.block;
                uint256 supplySpeed = comptroller.compSupplySpeeds(_cTokenAddress);

                if (supplySpeed > 0) {
                    uint256 supplyTokens = ICToken(_cTokenAddress).totalSupply();
                    uint256 compAccrued = deltaBlocks * supplySpeed;
                    uint256 ratio = supplyTokens > 0 ? (compAccrued * 1e36) / supplyTokens : 0;

                    return supplyState.index + ratio;
                } else return supplyState.index;
            }
        }
    }

    /// @notice Returns the updated COMP borrow index.
    /// @param _cTokenAddress The cToken address.
    /// @return The updated COMP borrow index.
    function getUpdatedBorrowIndex(address _cTokenAddress) public view returns (uint256) {
        IComptroller.CompMarketState memory localBorrowState = rewardsManager
        .getLocalCompBorrowState(_cTokenAddress);
        uint256 blockNumber = block.number;

        if (localBorrowState.block == blockNumber) return localBorrowState.index;
        else {
            IComptroller.CompMarketState memory borrowState = comptroller.compBorrowState(
                _cTokenAddress
            );

            if (borrowState.block == blockNumber) return borrowState.index;
            else {
                uint256 deltaBlocks = blockNumber - borrowState.block;
                uint256 borrowSpeed = comptroller.compBorrowSpeeds(_cTokenAddress);

                if (borrowSpeed > 0) {
                    uint256 borrowAmount = ICToken(_cTokenAddress).totalBorrows().div(
                        ICToken(_cTokenAddress).borrowIndex()
                    );
                    uint256 compAccrued = deltaBlocks * borrowSpeed;
                    uint256 ratio = borrowAmount > 0 ? (compAccrued * 1e36) / borrowAmount : 0;

                    return borrowState.index + ratio;
                } else return borrowState.index;
            }
        }
    }
}
