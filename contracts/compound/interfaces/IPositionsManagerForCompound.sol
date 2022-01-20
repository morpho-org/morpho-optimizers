// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "./IMarketsManagerForCompound.sol";

interface IPositionsManagerForCompound {
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

    function liquidate(address _poolTokenBorrowedAddress, address _poolTokenCollateralAddress, address _borrower, uint256 _amount) external;
}