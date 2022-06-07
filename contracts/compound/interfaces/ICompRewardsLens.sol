// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./compound/ICompound.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

interface ICompRewardsLens {
    function getUserUnclaimedRewards(address[] calldata _cTokenAddresses, address _user)
        external
        view
        returns (uint256 unclaimedRewards);

    function getAccruedSupplierComp(
        address _supplier,
        address _cTokenAddress,
        uint256 _balance
    ) external view returns (uint256);

    function getAccruedBorrowerComp(
        address _borrower,
        address _cTokenAddress,
        uint256 _balance
    ) external view returns (uint256);

    function getUpdatedSupplyIndex(address _cTokenAddress) external view returns (uint256);

    function getUpdatedBorrowIndex(address _cTokenAddress) external view returns (uint256);
}
