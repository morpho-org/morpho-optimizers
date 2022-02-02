// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
}
