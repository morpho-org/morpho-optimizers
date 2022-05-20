// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../RewardsManagerForAave.sol";

contract RewardsManagerForAaveOnMainnetAndAvalanche is RewardsManagerForAave {
    constructor(
        ILendingPool _lendingPool,
        IPositionsManagerForAave _positionsManager,
        address _swapManager
    ) RewardsManagerForAave(_lendingPool, _positionsManager, _swapManager) {}

    /// @inheritdoc RewardsManagerForAave
    function _getUpdatedIndex(address _asset, uint256 _totalBalance)
        internal
        override
        returns (uint256 newIndex)
    {
        LocalAssetData storage localData = localAssetData[_asset];
        uint256 blockTimestamp = block.timestamp;
        uint256 lastTimestamp = localData.lastUpdateTimestamp;
        if (blockTimestamp == lastTimestamp) return localData.lastIndex;
        else {
            (
                uint256 oldIndex,
                uint256 emissionPerSecond,
                uint256 lastTimestampOnAave
            ) = aaveIncentivesController.getAssetData(_asset);

            newIndex = _getAssetIndex(
                oldIndex,
                emissionPerSecond,
                lastTimestampOnAave,
                _totalBalance
            );
            localData.lastUpdateTimestamp = blockTimestamp;
            localData.lastIndex = newIndex;
        }
    }

    /// @inheritdoc RewardsManagerForAave
    function _getNewIndex(address _asset, uint256 _totalBalance)
        internal
        view
        override
        returns (uint256 newIndex)
    {
        LocalAssetData storage localData = localAssetData[_asset];
        uint256 blockTimestamp = block.timestamp;
        uint256 lastTimestamp = localData.lastUpdateTimestamp;
        if (blockTimestamp == lastTimestamp) return localData.lastIndex;
        else {
            (
                uint256 oldIndex,
                uint256 emissionPerSecond,
                uint256 lastTimestampOnAave
            ) = aaveIncentivesController.getAssetData(_asset);

            newIndex = _getAssetIndex(
                oldIndex,
                emissionPerSecond,
                lastTimestampOnAave,
                _totalBalance
            );
        }
    }
}
