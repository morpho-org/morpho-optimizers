// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/IRewardsManagerForCompound.sol";
import "./interfaces/compound/ICompound.sol";

import {LibStorage, MarketsStorage, PositionsStorage} from "./libraries/LibStorage.sol";
import "./libraries/LibPositionsManagerGetters.sol";
import "../common/libraries/DoubleLinkedList.sol";
import "./libraries/CompoundMath.sol";
import "./libraries/Types.sol";

contract MorphoLensForCompound {
    using DoubleLinkedList for DoubleLinkedList.List;
    using CompoundMath for uint256;

    /// STORAGE GETTERS ///

    function ms() internal pure returns (MarketsStorage storage) {
        return LibStorage.marketsStorage();
    }

    function ps() internal pure returns (PositionsStorage storage) {
        return LibStorage.positionsStorage();
    }

    /// GETTERS ///

    /// @notice Gets the head of the data structure on a specific market (for UI).
    /// @param _poolTokenAddress The address of the market from which to get the head.
    /// @param _positionType The type of user from which to get the head.
    /// @return head The head in the data structure.
    function getHead(address _poolTokenAddress, Types.PositionType _positionType)
        external
        view
        returns (address head)
    {
        if (_positionType == Types.PositionType.SUPPLIERS_IN_P2P)
            head = ps().suppliersInP2P[_poolTokenAddress].getHead();
        else if (_positionType == Types.PositionType.SUPPLIERS_ON_POOL)
            head = ps().suppliersOnPool[_poolTokenAddress].getHead();
        else if (_positionType == Types.PositionType.BORROWERS_IN_P2P)
            head = ps().borrowersInP2P[_poolTokenAddress].getHead();
        else if (_positionType == Types.PositionType.BORROWERS_ON_POOL)
            head = ps().borrowersOnPool[_poolTokenAddress].getHead();
    }

    /// @notice Gets the next user after `_user` in the data structure on a specific market (for UI).
    /// @param _poolTokenAddress The address of the market from which to get the user.
    /// @param _positionType The type of user from which to get the next user.
    /// @param _user The address of the user from which to get the next user.
    /// @return next The next user in the data structure.
    function getNext(
        address _poolTokenAddress,
        Types.PositionType _positionType,
        address _user
    ) external view returns (address next) {
        if (_positionType == Types.PositionType.SUPPLIERS_IN_P2P)
            next = ps().suppliersInP2P[_poolTokenAddress].getNext(_user);
        else if (_positionType == Types.PositionType.SUPPLIERS_ON_POOL)
            next = ps().suppliersOnPool[_poolTokenAddress].getNext(_user);
        else if (_positionType == Types.PositionType.BORROWERS_IN_P2P)
            next = ps().borrowersInP2P[_poolTokenAddress].getNext(_user);
        else if (_positionType == Types.PositionType.BORROWERS_ON_POOL)
            next = ps().borrowersOnPool[_poolTokenAddress].getNext(_user);
    }

    /// @notice Returns the maximum amount available to withdraw and borrow for `_user` related to `_poolTokenAddress` (in underlyings).
    /// @dev Note: must be called after calling `accrueInterest()` on the cToken to have the most up to date values.
    /// @param _user The user to determine the capacities for.
    /// @param _poolTokenAddress The address of the market.
    /// @return withdrawable The maximum withdrawable amount of underlying token allowed (in underlying).
    /// @return borrowable The maximum borrowable amount of underlying token allowed (in underlying).
    function getUserMaxCapacitiesForAsset(address _user, address _poolTokenAddress)
        external
        view
        returns (uint256 withdrawable, uint256 borrowable)
    {
        Types.LiquidityData memory data;
        Types.AssetLiquidityData memory assetData;
        ICompoundOracle oracle = ICompoundOracle(ms().comptroller.oracle());
        uint256 numberOfEnteredMarkets = ps().enteredMarkets[_user].length;
        uint256 i;

        while (i < numberOfEnteredMarkets) {
            address poolTokenEntered = ps().enteredMarkets[_user][i];

            if (_poolTokenAddress != poolTokenEntered) {
                assetData = LibPositionsManagerGetters.getUserLiquidityDataForAsset(
                    _user,
                    poolTokenEntered,
                    oracle
                );

                unchecked {
                    data.maxDebtValue += assetData.maxDebtValue;
                    data.debtValue += assetData.debtValue;
                }
            }

            unchecked {
                ++i;
            }
        }

        assetData = LibPositionsManagerGetters.getUserLiquidityDataForAsset(
            _user,
            _poolTokenAddress,
            oracle
        );

        unchecked {
            data.maxDebtValue += assetData.maxDebtValue;
            data.debtValue += assetData.debtValue;
        }

        // Not possible to withdraw nor borrow.
        if (data.maxDebtValue < data.debtValue) return (0, 0);

        uint256 differenceInUnderlying = (data.maxDebtValue - data.debtValue).div(
            assetData.underlyingPrice
        );

        withdrawable = assetData.collateralValue.div(assetData.underlyingPrice);
        if (assetData.collateralFactor != 0) {
            withdrawable = Math.min(
                withdrawable,
                differenceInUnderlying.div(assetData.collateralFactor)
            );
        }

        borrowable = differenceInUnderlying;
    }

    function rewardsManager() external view returns (IRewardsManagerForCompound rewardsManager_) {
        rewardsManager_ = ps().rewardsManager;
    }

    function treasuryVault() external view returns (address treasuryVault_) {
        treasuryVault_ = ps().treasuryVault;
    }

    function incentivesVault() external view returns (address incentivesVault_) {
        incentivesVault_ = address(ps().incentivesVault);
    }

    function isCompRewardsActive() external view returns (bool isCompRewardsActive_) {
        isCompRewardsActive_ = ps().isCompRewardsActive;
    }

    function paused(address _poolTokenAddress) external view returns (bool isPaused_) {
        isPaused_ = ps().paused[_poolTokenAddress];
    }

    function NDS() external view returns (uint8 NDS_) {
        NDS_ = ps().NDS;
    }

    function maxGas()
        external
        view
        returns (
            uint64 maxGasSupply_,
            uint64 maxGasBorrow_,
            uint64 maxGasWithdraw_,
            uint64 maxGasRepay_
        )
    {
        maxGasSupply_ = ps().maxGas.supply;
        maxGasBorrow_ = ps().maxGas.borrow;
        maxGasWithdraw_ = ps().maxGas.withdraw;
        maxGasRepay_ = ps().maxGas.repay;
    }

    function getUserBalanceStates(address _user)
        external
        view
        returns (
            uint256 collateralValue,
            uint256 debtValue,
            uint256 maxDebtValue
        )
    {
        (collateralValue, debtValue, maxDebtValue) = LibPositionsManagerGetters
        .getUserBalanceStates(_user);
    }

    function getUserLiquidityDataForAsset(
        address _user,
        address _poolTokenAddress,
        ICompoundOracle _oracle
    ) external view returns (Types.AssetLiquidityData memory) {
        return
            LibPositionsManagerGetters.getUserLiquidityDataForAsset(
                _user,
                _poolTokenAddress,
                _oracle
            );
    }

    function deltas(address _poolTokenAddress)
        external
        view
        returns (
            uint256 supplyP2PDelta_,
            uint256 borrowP2PDelta_,
            uint256 supplyP2PAmount_,
            uint256 borrowP2PAmount_
        )
    {
        supplyP2PDelta_ = ps().deltas[_poolTokenAddress].supplyP2PDelta;
        borrowP2PDelta_ = ps().deltas[_poolTokenAddress].borrowP2PDelta;
        supplyP2PAmount_ = ps().deltas[_poolTokenAddress].supplyP2PAmount;
        borrowP2PAmount_ = ps().deltas[_poolTokenAddress].borrowP2PAmount;
    }

    function enteredMarkets(address _user, uint256 _index)
        external
        view
        returns (address poolTokenAddress_)
    {
        poolTokenAddress_ = ps().enteredMarkets[_user][_index];
    }
}
