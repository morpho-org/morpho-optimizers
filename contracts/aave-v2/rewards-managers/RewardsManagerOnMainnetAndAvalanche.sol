// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../RewardsManager.sol";

/// @title RewardsManagerOnMainnetAndAvalanche.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice This contract is used to manage the rewards from the Aave protocol on Mainnet or Avalanche.
contract RewardsManagerOnMainnetAndAvalanche is RewardsManager {
    /// @inheritdoc RewardsManager
    function _getAssetIndex(
        IAaveIncentivesController _aaveIncentivesController,
        address _asset,
        uint256 _totalBalance
    ) internal view override returns (uint256 oldIndex, uint256 newIndex) {
        if (localAssetData[_asset].lastUpdateTimestamp == block.timestamp)
            oldIndex = newIndex = localAssetData[_asset].lastIndex;
        else {
            (
                uint256 oldIndexOnAave,
                uint256 emissionPerSecond,
                uint256 lastTimestampOnAave
            ) = _aaveIncentivesController.getAssetData(_asset);

            oldIndex = localAssetData[_asset].lastIndex;
            newIndex = _computeIndex(
                _aaveIncentivesController,
                oldIndexOnAave,
                emissionPerSecond,
                lastTimestampOnAave,
                _totalBalance
            );
        }
    }
}
