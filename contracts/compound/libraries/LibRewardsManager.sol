// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../interfaces/compound/ICompound.sol";

import {LibStorage, PositionsStorage, RewardsStorage} from "./LibStorage.sol";
import "./CompoundMath.sol";

library LibRewardsManager {
    using CompoundMath for uint256;

    /// STORAGE ///

    uint224 public constant COMP_INITIAL_INDEX = 1e36;

    /// ERRORS ///

    /// @notice Thrown when an invalid cToken address is passed to accrue rewards.
    error InvalidCToken();

    /// STORAGE GETTERS ///

    function ps() internal pure returns (PositionsStorage storage) {
        return LibStorage.positionsStorage();
    }

    function rs() internal pure returns (RewardsStorage storage) {
        return LibStorage.rewardsStorage();
    }

    /// INTERNAL ///

    /// @dev Updates the unclaimed COMP rewards of the user.
    /// @param _user The address of the user.
    /// @param _cTokenAddress The cToken address.
    /// @param _userBalance The user balance of tokens in the distribution.
    function accrueUserSupplyUnclaimedRewards(
        address _user,
        address _cTokenAddress,
        uint256 _userBalance
    ) public {
        updateSupplyIndex(_cTokenAddress);
        rs().userUnclaimedCompRewards[_user] += updateSupplyIndex(
            _user,
            _cTokenAddress,
            _userBalance
        );
    }

    /// @dev Updates the unclaimed COMP rewards of the user.
    /// @param _user The address of the user.
    /// @param _cTokenAddress The cToken address.
    /// @param _userBalance The user balance of tokens in the distribution.
    function accrueUserBorrowUnclaimedRewards(
        address _user,
        address _cTokenAddress,
        uint256 _userBalance
    ) public {
        updateBorrowIndex(_cTokenAddress);
        rs().userUnclaimedCompRewards[_user] += accrueBorrowerComp(
            _user,
            _cTokenAddress,
            _userBalance
        );
    }

    /// @dev Returns the unclaimed COMP rewards for the given cToken addresses.
    /// @param _cTokenAddresses The cToken addresses for which to compute the rewards.
    /// @param _user The address of the user.
    function getUserUnclaimedRewards(address[] calldata _cTokenAddresses, address _user)
        public
        view
        returns (uint256 unclaimedRewards)
    {
        unclaimedRewards = rs().userUnclaimedCompRewards[_user];

        PositionsStorage storage p = ps();

        for (uint256 i; i < _cTokenAddresses.length; i++) {
            address cTokenAddress = _cTokenAddresses[i];

            (bool isListed, , ) = p.comptroller.markets(cTokenAddress);
            if (!isListed) revert InvalidCToken();

            unclaimedRewards += getAccruedSupplierComp(
                _user,
                cTokenAddress,
                p.supplyBalanceInOf[cTokenAddress][_user].onPool
            );
            unclaimedRewards += getAccruedBorrowerComp(
                _user,
                cTokenAddress,
                p.borrowBalanceInOf[cTokenAddress][_user].onPool
            );
        }
    }

    /// @dev Accrues unclaimed COMP rewards for the cToken addresses and returns the total unclaimed COMP rewards.
    /// @param _cTokenAddresses The cToken addresses for which to accrue rewards.
    /// @param _user The address of the user.
    /// @return unclaimedRewards The user unclaimed rewards.
    function accrueUserUnclaimedRewards(address[] calldata _cTokenAddresses, address _user)
        public
        returns (uint256 unclaimedRewards)
    {
        RewardsStorage storage r = rs();
        PositionsStorage storage p = ps();
        unclaimedRewards = r.userUnclaimedCompRewards[_user];

        for (uint256 i; i < _cTokenAddresses.length; i++) {
            address cTokenAddress = _cTokenAddresses[i];

            (bool isListed, , ) = p.comptroller.markets(cTokenAddress);
            if (!isListed) revert InvalidCToken();

            updateSupplyIndex(cTokenAddress);
            unclaimedRewards += updateSupplyIndex(
                _user,
                cTokenAddress,
                p.supplyBalanceInOf[cTokenAddress][_user].onPool
            );

            updateBorrowIndex(cTokenAddress);
            unclaimedRewards += accrueBorrowerComp(
                _user,
                cTokenAddress,
                p.borrowBalanceInOf[cTokenAddress][_user].onPool
            );
        }

        r.userUnclaimedCompRewards[_user] = unclaimedRewards;
    }

    /// @dev Returns the accrued COMP rewards of a user since the last update.
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
        uint256 supplierIndex = rs().compSupplierIndex[_cTokenAddress][_supplier];

        if (supplierIndex == 0) return 0;
        return (_balance * (supplyIndex - supplierIndex)) / 1e36;
    }

    /// @dev Returns the accrued COMP rewards of a user since the last update.
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
        uint256 borrowerIndex = rs().compBorrowerIndex[_cTokenAddress][_borrower];

        if (borrowerIndex == 0) return 0;
        return (_balance * (borrowIndex - borrowerIndex)) / 1e36;
    }

    /// @dev Returns the udpated COMP supply index.
    /// @param _cTokenAddress The cToken address.
    /// @return The updated COMP supply index.
    function getUpdatedSupplyIndex(address _cTokenAddress) public view returns (uint256) {
        IComptroller.CompMarketState memory localSupplyState = rs().localCompSupplyState[
            _cTokenAddress
        ];
        uint256 blockNumber = block.number;

        if (localSupplyState.block == blockNumber) return localSupplyState.index;
        else {
            IComptroller.CompMarketState memory supplyState = ps().comptroller.compSupplyState(
                _cTokenAddress
            );

            if (supplyState.block == blockNumber) return supplyState.index;
            else {
                uint256 deltaBlocks = localSupplyState.block == 0
                    ? blockNumber - supplyState.block
                    : blockNumber - localSupplyState.block;
                uint256 supplySpeed = ps().comptroller.compSupplySpeeds(_cTokenAddress);

                if (supplySpeed > 0) {
                    uint256 supplyTokens = ICToken(_cTokenAddress).totalSupply();
                    uint256 compAccrued = deltaBlocks * supplySpeed;
                    uint256 ratio = supplyTokens > 0 ? (compAccrued * 1e36) / supplyTokens : 0;
                    uint256 formerIndex = localSupplyState.index == 0
                        ? supplyState.index
                        : localSupplyState.index;
                    return formerIndex + ratio;
                } else return supplyState.index;
            }
        }
    }

    /// @dev Returns the udpated COMP borrow index.
    /// @param _cTokenAddress The cToken address.
    /// @return The updated COMP borrow index.
    function getUpdatedBorrowIndex(address _cTokenAddress) public view returns (uint256) {
        IComptroller.CompMarketState memory localBorrowState = rs().localCompBorrowState[
            _cTokenAddress
        ];
        uint256 blockNumber = block.number;

        if (localBorrowState.block == blockNumber) return localBorrowState.index;
        else {
            IComptroller.CompMarketState memory borrowState = ps().comptroller.compBorrowState(
                _cTokenAddress
            );

            if (borrowState.block == blockNumber) return borrowState.index;
            else {
                uint256 deltaBlocks = localBorrowState.block == 0
                    ? blockNumber - borrowState.block
                    : blockNumber - localBorrowState.block;
                uint256 borrowSpeed = ps().comptroller.compBorrowSpeeds(_cTokenAddress);

                if (borrowSpeed > 0) {
                    uint256 borrowAmount = ICToken(_cTokenAddress).totalBorrows().div(
                        ICToken(_cTokenAddress).borrowIndex()
                    );
                    uint256 compAccrued = deltaBlocks * borrowSpeed;
                    uint256 ratio = borrowAmount > 0 ? (compAccrued * 1e36) / borrowAmount : 0;
                    uint256 formerIndex = localBorrowState.index == 0
                        ? borrowState.index
                        : localBorrowState.index;
                    return formerIndex + ratio;
                } else return borrowState.index;
            }
        }
    }

    /// INTERNAL ///

    /// @dev Updates supplier index and returns the accrued COMP rewards of the supplier since the last update.
    /// @param _supplier The address of the supplier.
    /// @param _cTokenAddress The cToken address.
    /// @param _balance The user balance of tokens in the distribution.
    /// @return The accrued COMP rewards.
    function updateSupplyIndex(
        address _supplier,
        address _cTokenAddress,
        uint256 _balance
    ) public returns (uint256) {
        RewardsStorage storage r = rs();
        uint256 supplyIndex = r.localCompSupplyState[_cTokenAddress].index;
        uint256 supplierIndex = r.compSupplierIndex[_cTokenAddress][_supplier];
        r.compSupplierIndex[_cTokenAddress][_supplier] = supplyIndex;

        if (supplierIndex == 0) return 0;
        return (_balance * (supplyIndex - supplierIndex)) / 1e36;
    }

    /// @dev Updates borrower index and returns the accrued COMP rewards of the borrower since the last update.
    /// @param _borrower The address of the borrower.
    /// @param _cTokenAddress The cToken address.
    /// @param _balance The user balance of tokens in the distribution.
    /// @return The accrued COMP rewards.
    function accrueBorrowerComp(
        address _borrower,
        address _cTokenAddress,
        uint256 _balance
    ) public returns (uint256) {
        RewardsStorage storage r = rs();
        uint256 borrowIndex = r.localCompBorrowState[_cTokenAddress].index;
        uint256 borrowerIndex = r.compBorrowerIndex[_cTokenAddress][_borrower];
        r.compBorrowerIndex[_cTokenAddress][_borrower] = borrowIndex;

        if (borrowerIndex == 0) return 0;
        return (_balance * (borrowIndex - borrowerIndex)) / 1e36;
    }

    /// @dev Updates the COMP supply index.
    /// @param _cTokenAddress The cToken address.
    function updateSupplyIndex(address _cTokenAddress) public {
        RewardsStorage storage r = rs();
        IComptroller.CompMarketState storage localSupplyState = r.localCompSupplyState[
            _cTokenAddress
        ];
        uint256 blockNumber = block.number;

        if (localSupplyState.block == blockNumber) return;
        else {
            IComptroller.CompMarketState memory supplyState = ps().comptroller.compSupplyState(
                _cTokenAddress
            );

            if (supplyState.block == blockNumber) {
                localSupplyState.block = supplyState.block;
                localSupplyState.index = supplyState.index;
            } else {
                uint256 deltaBlocks = localSupplyState.block == 0
                    ? blockNumber - supplyState.block
                    : blockNumber - localSupplyState.block;
                uint256 supplySpeed = ps().comptroller.compSupplySpeeds(_cTokenAddress);

                if (supplySpeed > 0) {
                    uint256 supplyTokens = ICToken(_cTokenAddress).totalSupply();
                    uint256 compAccrued = deltaBlocks * supplySpeed;
                    uint256 ratio = supplyTokens > 0 ? (compAccrued * 1e36) / supplyTokens : 0;
                    uint256 formerIndex = localSupplyState.index == 0
                        ? supplyState.index
                        : localSupplyState.index;
                    uint256 index = formerIndex + ratio;
                    r.localCompSupplyState[_cTokenAddress] = IComptroller.CompMarketState({
                        index: CompoundMath.safe224(index),
                        block: CompoundMath.safe32(blockNumber)
                    });
                } else localSupplyState.block = CompoundMath.safe32(blockNumber);
            }
        }
    }

    /// @dev Updates the COMP borrow index.
    /// @param _cTokenAddress The cToken address.
    function updateBorrowIndex(address _cTokenAddress) public {
        RewardsStorage storage r = rs();
        IComptroller.CompMarketState storage localBorrowState = r.localCompBorrowState[
            _cTokenAddress
        ];
        uint256 blockNumber = block.number;

        if (localBorrowState.block == blockNumber) return;
        else {
            IComptroller.CompMarketState memory borrowState = ps().comptroller.compBorrowState(
                _cTokenAddress
            );

            if (borrowState.block == blockNumber) {
                localBorrowState.block = borrowState.block;
                localBorrowState.index = borrowState.index;
            } else {
                uint256 deltaBlocks = localBorrowState.block == 0
                    ? blockNumber - borrowState.block
                    : blockNumber - localBorrowState.block;
                uint256 borrowSpeed = ps().comptroller.compBorrowSpeeds(_cTokenAddress);

                if (borrowSpeed > 0) {
                    uint256 borrowAmount = ICToken(_cTokenAddress).totalBorrows().div(
                        ICToken(_cTokenAddress).borrowIndex()
                    );
                    uint256 compAccrued = deltaBlocks * borrowSpeed;
                    uint256 ratio = borrowAmount > 0 ? (compAccrued * 1e36) / borrowAmount : 0;
                    uint256 formerIndex = localBorrowState.index == 0
                        ? borrowState.index
                        : localBorrowState.index;
                    uint256 index = formerIndex + ratio;
                    localBorrowState.index = CompoundMath.safe224(index);
                    localBorrowState.block = CompoundMath.safe32(blockNumber);
                } else localBorrowState.block = CompoundMath.safe32(blockNumber);
            }
        }
    }
}
