// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

interface IMorpho {
    enum Threshold {
        Underlying,
        CToken,
        MUnit,
        CdUnit
    }

    function isListed(address _marketAddress) external returns (bool);

    function BPY(address _marketAddress) external returns (uint256);

    function collateralFactor(address _marketAddress) external returns (uint256);

    function liquidationIncentive(address _marketAddress) external returns (uint256);

    function mUnitExchangeRate(address _marketAddress) external returns (uint256);

    function lastUpdateBlockNumber(address _marketAddress) external returns (uint256);

    function thresholds(address _marketAddress, Threshold _thresholdType)
        external
        returns (uint256);

    function updateMUnitExchangeRate(address _marketAddress) external returns (uint256);
}
