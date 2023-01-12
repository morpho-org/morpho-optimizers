// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import "../../interfaces/compound/ICompound.sol";
import "../../interfaces/IRewardsManager.sol";
import "../../interfaces/IMorpho.sol";

interface ILensExtension {
    function morpho() external view returns (IMorpho);

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
