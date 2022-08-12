// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../RewardsManager.sol";

/// @title RewardsManagerOnPolygon.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice This contract is used to manage the rewards from the Aave protocol on Polygon.
contract RewardsManagerOnPolygon is RewardsManager {
    /// @inheritdoc RewardsManager
    function _getAssetIndex(
        IAaveIncentivesController _aaveIncentivesController,
        address _asset,
        uint256 _totalBalance
    ) internal view override returns (uint256 oldIndex, uint256 newIndex) {
        if (localAssetData[_asset].lastUpdateTimestamp == block.timestamp)
            oldIndex = newIndex = localAssetData[_asset].lastIndex;
        else {
            IAaveIncentivesController.AssetData memory assetData = _aaveIncentivesController.assets(
                _asset
            );

            oldIndex = localAssetData[_asset].lastIndex;
            newIndex = _computeIndex(
                _aaveIncentivesController,
                assetData.index,
                assetData.emissionPerSecond,
                assetData.lastUpdateTimestamp,
                _totalBalance
            );
        }
    }
}
