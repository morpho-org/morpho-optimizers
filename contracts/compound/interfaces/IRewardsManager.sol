// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./compound/ICompound.sol";

interface IRewardsManager {
    function claimRewards(address[] calldata, address) external returns (uint256);

    function accrueUserUnclaimedRewards(address[] calldata _cTokenAddresses, address)
        external
        returns (uint256);

    function userUnclaimedCompRewards(address) external view returns (uint256);

    function getUserUnclaimedRewards(address[] calldata _cTokenAddresses, address _user)
        external
        returns (uint256 unclaimedRewards);

    function compSupplierIndex(address, address) external view returns (uint256);

    function compBorrowerIndex(address, address) external view returns (uint256);

    function getLocalCompSupplyState(address)
        external
        view
        returns (IComptroller.CompMarketState memory);

    function getLocalCompBorrowState(address)
        external
        view
        returns (IComptroller.CompMarketState memory);

    function getUpdatedSupplyIndex(address) external view returns (uint256);

    function getUpdatedBorrowIndex(address) external view returns (uint256);

    function accrueUserSupplyUnclaimedRewards(
        address,
        address,
        uint256
    ) external;

    function accrueUserBorrowUnclaimedRewards(
        address,
        address,
        uint256
    ) external;
}
