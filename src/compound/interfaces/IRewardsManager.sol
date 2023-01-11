// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import "./compound/ICompound.sol";

interface IRewardsManager {
    function initialize(address _morpho) external;

    function claimRewards(address[] calldata, address) external returns (uint256);

    function userUnclaimedCompRewards(address) external view returns (uint256);

    function compSupplierIndex(address, address) external view returns (uint256);

    function compBorrowerIndex(address, address) external view returns (uint256);

    function getLocalCompSupplyState(address _cTokenAddress)
        external
        view
        returns (IComptroller.CompMarketState memory);

    function getLocalCompBorrowState(address _cTokenAddress)
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

    function getUserUnclaimedRewards(address[] calldata _poolTokens, address _user)
        external
        view
        returns (uint256 unclaimedRewards);

    function getAccruedSupplierComp(
        address _supplier,
        address _poolToken,
        uint256 _balance
    ) external view returns (uint256);

    function getAccruedBorrowerComp(
        address _borrower,
        address _poolToken,
        uint256 _balance
    ) external view returns (uint256);

    function getAccruedSupplierComp(address _supplier, address _poolToken)
        external
        view
        returns (uint256);

    function getAccruedBorrowerComp(address _borrower, address _poolToken)
        external
        view
        returns (uint256);

    function getCurrentCompSupplyIndex(address _poolToken) external view returns (uint256);

    function getCurrentCompBorrowIndex(address _poolToken) external view returns (uint256);
}
