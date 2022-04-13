// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./compound/ICompound.sol";

interface IRewardsManagerForCompound {
    function claimRewards(address[] calldata, address) external returns (uint256);

    function accrueUserUnclaimedRewards(address[] calldata _cTokenAddresses, address)
        external
        view
        returns (uint256);

    function userUnclaimedCompRewards(address) external view returns (uint256);

    function getUserUnclaimedRewards(address[] calldata _cTokenAddresses, address _user)
        external
        returns (uint256 unclaimedRewards);

    function compSupplierIndex(address, address) external view returns (uint256);

    function compBorrowerIndex(address, address) external view returns (uint256);

    function localCompSupplyState(address)
        external
        view
        returns (IComptroller.CompMarketState memory);

    function localCompBorrowState(address)
        external
        view
        returns (IComptroller.CompMarketState memory);

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
