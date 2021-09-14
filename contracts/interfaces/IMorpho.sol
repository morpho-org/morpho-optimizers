// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

interface IMorpho {
    function liquidationIncentive() external returns (uint256);

    function isListed(address _cErc20Address) external returns (bool);

    function BPY(address _cErc20Address) external returns (uint256);

    function collateralFactor(address _cErc20Address) external returns (uint256);

    function mUnitExchangeRate(address _cErc20Address) external returns (uint256);

    function lastUpdateBlockNumber(address _cErc20Address) external returns (uint256);

    function thresholds(address _cErc20Address, uint256 _thresholdType) external returns (uint256);

    function updateMUnitExchangeRate(address _cErc20Address) external returns (uint256);
}
