// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./dependencies/@openzeppelin/IReentrancyGuard.sol";

interface IPositionsManagerForCompound is IReentrancyGuard {
    function NMAX() external view returns (uint16);

    function CTOKEN_DECIMALS() external view returns (uint8);

    function accountMembership(address, address) external view returns (bool);

    function enteredMarkets(address) external view returns (address[] memory);

    function threshold(address) external view returns (uint256);

    function createMarket(address _poolTokenAddress) external returns (uint256[] memory);

    function setNmaxForMatchingEngine(uint16 _newMaxNumber) external;

    function setThreshold(address _poolTokenAddress, uint256 _newThreshold) external;

    function supply(address _poolTokenAddress, uint256 _amount) external;

    function borrow(address _poolTokenAddress, uint256 _amount) external;

    function withdraw(address _poolTokenAddress, uint256 _amount) external;

    function repay(address _poolTokenAddress, uint256 _amount) external;

    function liquidate(
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address _borrower,
        uint256 _amount
    ) external;
}
