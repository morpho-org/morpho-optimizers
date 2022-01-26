// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./IPositionsManagerForAaveStorage.sol";

interface IPositionsManagerForAave is IPositionsManagerForAaveStorage {
    function updateAaveContracts() external;

    function setAaveIncentivesController(address _aaveIncentivesController) external;

    function setNmaxForMatchingEngine(uint16 _newMaxNumber) external;

    function setThreshold(address _poolTokenAddress, uint256 _newThreshold) external;

    function setCapValue(address _poolTokenAddress, uint256 _newCapValue) external;

    function setTreasuryVault(address _newTreasuryVaultAddress) external;

    function setRewardsManager(address _rewardsManagerAddress) external;

    function claimToTreasury(address _poolTokenAddress) external;

    function claimRewards(address[] calldata _assets) external;

    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode
    ) external;

    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode
    ) external;

    function withdraw(address _poolTokenAddress, uint256 _amount) external;

    function repay(address _poolTokenAddress, uint256 _amount) external;

    function liquidate(
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address _borrower,
        uint256 _amount
    ) external;

    function getUserBalanceStates(address _user)
        external
        returns (
            uint256 collateralValue,
            uint256 debtValue,
            uint256 maxDebtValue
        );

    function getUserMaxCapacitiesForAsset(address _user, address _poolTokenAddress)
        external
        returns (uint256 withdrawable, uint256 borrowable);
}
