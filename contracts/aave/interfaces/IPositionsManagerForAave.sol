// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./aave/IProtocolDataProvider.sol";
import "./IRewardsManager.sol";
import "./aave/ILendingPool.sol";

interface IPositionsManagerForAave {
    struct Balance {
        uint256 inP2P;
        uint256 onPool;
    }

    function createMarket(address) external returns (uint256[] memory);

    function getUserMaxCapacitiesForAsset(address _user, address _poolTokenAddress)
        external
        view
        returns (uint256 withdrawable, uint256 borrowable);

    function setNmaxForMatchingEngine(uint16) external;

    function setThreshold(address, uint256) external;

    function setCapValue(address, uint256) external;

    function setTreasuryVault(address) external;

    function setRewardsManager(address _rewardsManagerAddress) external;

    function borrowBalanceInOf(address, address) external returns (Balance memory);

    function supplyBalanceInOf(address, address) external returns (Balance memory);

    function _supplyERC20ToPool(IERC20, uint256) external;

    function _withdrawERC20FromPool(IERC20, uint256) external;

    function _borrowERC20FromPool(IERC20, uint256) external;

    function _repayERC20ToPool(
        IERC20,
        uint256,
        uint256
    ) external;

    function updateSupplyBalanceInOfOnPool(
        address,
        address,
        int256
    ) external;

    function updateSupplyBalanceInOfInP2P(
        address,
        address,
        int256
    ) external;

    function updateBorrowBalanceInOfOnPool(
        address,
        address,
        int256
    ) external;

    function updateBorrowBalanceInOfInP2P(
        address,
        address,
        int256
    ) external;

    function lendingPool() external returns (ILendingPool);

    function dataProvider() external returns (IProtocolDataProvider);

    function rewardsManager() external returns (IRewardsManager);

    function SUPPLIERS_IN_P2P() external returns (uint8);

    function SUPPLIERS_ON_POOL() external returns (uint8);

    function BORROWERS_IN_P2P() external returns (uint8);

    function BORROWERS_ON_POOL() external returns (uint8);
}
