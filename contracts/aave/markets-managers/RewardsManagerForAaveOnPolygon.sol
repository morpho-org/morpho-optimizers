// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import "../RewardsManagerForAave.sol";

contract RewardsManagerForAaveOnPolygon is RewardsManagerForAave {
    constructor(IPool _pool, IPositionsManagerForAave _positionsManager)
        RewardsManagerForAave(_pool, _positionsManager)
    {}

    /// @inheritdoc RewardsManagerForAave
    function _getUpdatedIndex(address _asset, uint256 _totalStaked)
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

            if (blockTimestamp == lastTimestampOnAave) newIndex = oldIndex;
            else
                newIndex = _getAssetIndex(
                    oldIndex,
                    emissionPerSecond,
                    lastTimestampOnAave,
                    _totalStaked
                );
            localData.lastUpdateTimestamp = blockTimestamp;
            localData.lastIndex = newIndex;
        }
    }
}
