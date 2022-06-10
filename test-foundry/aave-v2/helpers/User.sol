// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@contracts/aave-v2/interfaces/aave/ILendingPool.sol";
import "@contracts/aave-v2/interfaces/IRewardsManager.sol";

import "@contracts/aave-v2/Morpho.sol";

contract User {
    using SafeTransferLib for ERC20;

    Morpho internal morpho;
    IRewardsManager internal rewardsManager;
    ILendingPool public pool;
    IAaveIncentivesController public aaveIncentivesController;

    constructor(Morpho _morpho) {
        morpho = _morpho;
        rewardsManager = _morpho.rewardsManager();
        pool = _morpho.pool();
        aaveIncentivesController = _morpho.aaveIncentivesController();
    }

    receive() external payable {}

    function balanceOf(address _token) external view returns (uint256) {
        return ERC20(_token).balanceOf(address(this));
    }

    function approve(address _token, uint256 _amount) external {
        ERC20(_token).safeApprove(address(morpho), _amount);
    }

    function approve(
        address _token,
        address _spender,
        uint256 _amount
    ) external {
        ERC20(_token).safeApprove(_spender, _amount);
    }

    function createMarket(
        address _underlyingTokenAddress,
        Types.MarketParameters calldata _marketParams
    ) external {
        morpho.createMarket(_underlyingTokenAddress, _marketParams);
    }

    function setReserveFactor(address _poolTokenAddress, uint16 _reserveFactor) external {
        morpho.setReserveFactor(_poolTokenAddress, _reserveFactor);
    }

    function supply(address _poolTokenAddress, uint256 _amount) external {
        morpho.supply(_poolTokenAddress, address(this), _amount);
    }

    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external {
        morpho.supply(_poolTokenAddress, address(this), _amount, _maxGasForMatching);
    }

    function withdraw(address _poolTokenAddress, uint256 _amount) external {
        morpho.withdraw(_poolTokenAddress, _amount);
    }

    function borrow(address _poolTokenAddress, uint256 _amount) external {
        morpho.borrow(_poolTokenAddress, _amount);
    }

    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external {
        morpho.borrow(_poolTokenAddress, _amount, _maxGasForMatching);
    }

    function repay(address _poolTokenAddress, uint256 _amount) external {
        morpho.repay(_poolTokenAddress, address(this), _amount);
    }

    function aaveSupply(address _underlyingTokenAddress, uint256 _amount) external {
        ERC20(_underlyingTokenAddress).safeApprove(address(pool), type(uint256).max);
        pool.deposit(_underlyingTokenAddress, _amount, address(this), 0); // 0 : no refferal code
    }

    function aaveBorrow(address _underlyingTokenAddress, uint256 _amount) external {
        pool.borrow(_underlyingTokenAddress, _amount, 2, 0, address(this)); // 2 : variable rate | 0 : no refferal code
    }

    function aaveClaimRewards(address[] memory assets) external {
        aaveIncentivesController.claimRewards(assets, type(uint256).max, address(this));
    }

    function liquidate(
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address _borrower,
        uint256 _amount
    ) external {
        morpho.liquidate(
            _poolTokenBorrowedAddress,
            _poolTokenCollateralAddress,
            _borrower,
            _amount
        );
    }

    function setMaxSortedUsers(uint256 _newMaxSortedUsers) external {
        morpho.setMaxSortedUsers(_newMaxSortedUsers);
    }

    function setDefaultMaxGasForMatching(Types.MaxGasForMatching memory _maxGasForMatching)
        external
    {
        morpho.setDefaultMaxGasForMatching(_maxGasForMatching);
    }

    function claimRewards(address[] calldata _assets, bool _toSwap) external {
        morpho.claimRewards(_assets, _toSwap);
    }

    function setPauseStatus(address _marketAddress, bool _newStatus) external {
        morpho.setPauseStatus(_marketAddress, _newStatus);
    }

    function setPartialPauseStatus(address _poolTokenAddress, bool _newStatus) external {
        morpho.setPartialPauseStatus(_poolTokenAddress, _newStatus);
    }

    function setTreasuryVault(address _newTreasuryVault) external {
        morpho.setTreasuryVault(_newTreasuryVault);
    }

    function setAaveIncentivesControllerOnRewardsManager(address _aaveIncentivesController)
        external
    {
        rewardsManager.setAaveIncentivesController(_aaveIncentivesController);
    }
}
