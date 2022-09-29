// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

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
        address _underlyingToken,
        uint16 _reserveFactor,
        uint16 _p2pIndexCursor
    ) external {
        morpho.createMarket(_underlyingToken, _reserveFactor, _p2pIndexCursor);
    }

    function setReserveFactor(address _poolToken, uint16 _reserveFactor) external {
        morpho.setReserveFactor(_poolToken, _reserveFactor);
    }

    function supply(address _poolToken, uint256 _amount) external returns (uint256 supplied) {
        return morpho.supply(_poolToken, _amount);
    }

    function supply(
        address _poolToken,
        address _onBehalf,
        uint256 _amount
    ) external returns (uint256 supplied) {
        return morpho.supply(_poolToken, _onBehalf, _amount);
    }

    function supply(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external returns (uint256 supplied) {
        return morpho.supply(_poolToken, _amount, _maxGasForMatching);
    }

    function supply(
        address _poolToken,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external returns (uint256 supplied) {
        return morpho.supply(_poolToken, _onBehalf, _amount, _maxGasForMatching);
    }

    function borrow(address _poolToken, uint256 _amount) external returns (uint256 borrowed) {
        return morpho.borrow(_poolToken, _amount);
    }

    function borrow(
        address _poolToken,
        address _receiver,
        uint256 _amount
    ) external returns (uint256 borrowed) {
        return morpho.borrow(_poolToken, _receiver, _amount);
    }

    function borrow(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external returns (uint256 borrowed) {
        return morpho.borrow(_poolToken, _amount, _maxGasForMatching);
    }

    function borrow(
        address _poolToken,
        address _receiver,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external returns (uint256 borrowed) {
        return morpho.borrow(_poolToken, _receiver, _amount, _maxGasForMatching);
    }

    function withdraw(address _poolToken, uint256 _amount) external returns (uint256 withdrawn) {
        return morpho.withdraw(_poolToken, _amount);
    }

    function withdraw(
        address _poolToken,
        address _receiver,
        uint256 _amount
    ) external returns (uint256 withdrawn) {
        return morpho.withdraw(_poolToken, _receiver, _amount);
    }

    function repay(address _poolToken, uint256 _amount) external returns (uint256 repaid) {
        return morpho.repay(_poolToken, _amount);
    }

    function repay(
        address _poolToken,
        address _onBehalf,
        uint256 _amount
    ) public returns (uint256 repaid) {
        return morpho.repay(_poolToken, _onBehalf, _amount);
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
        address _poolTokenBorrowed,
        address _poolTokenCollateral,
        address _borrower,
        uint256 _amount
    ) external returns (uint256 repaid, uint256 seized) {
        (repaid, seized) = morpho.liquidate(
            _poolTokenBorrowed,
            _poolTokenCollateral,
            _borrower,
            _amount
        );
    }

    function liquidate(
        address _poolTokenBorrowed,
        address _poolTokenCollateral,
        address _borrower,
        address _receiver,
        uint256 _amount
    ) external returns (uint256 repaid, uint256 seized) {
        (repaid, seized) = morpho.liquidate(
            _poolTokenBorrowed,
            _poolTokenCollateral,
            _borrower,
            _receiver,
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

    function claimRewards(address[] calldata _assets, bool _toSwap)
        external
        returns (uint256 claimedAmount)
    {
        return morpho.claimRewards(_assets, _toSwap);
    }

    function setTreasuryVault(address _newTreasuryVault) external {
        morpho.setTreasuryVault(_newTreasuryVault);
    }

    function setIsSupplyPaused(address _poolToken, bool _isPaused) external {
        morpho.setIsSupplyPaused(_poolToken, _isPaused);
    }

    function setIsBorrowPaused(address _poolToken, bool _isPaused) external {
        morpho.setIsBorrowPaused(_poolToken, _isPaused);
    }

    function setIsWithdrawPaused(address _poolToken, bool _isPaused) external {
        morpho.setIsWithdrawPaused(_poolToken, _isPaused);
    }

    function setIsRepayPaused(address _poolToken, bool _isPaused) external {
        morpho.setIsRepayPaused(_poolToken, _isPaused);
    }

    function setIsLiquidateCollateralPaused(address _poolToken, bool _isPaused) external {
        morpho.setIsLiquidateCollateralPaused(_poolToken, _isPaused);
    }

    function setIsLiquidateBorrowPaused(address _poolToken, bool _isPaused) external {
        morpho.setIsLiquidateBorrowPaused(_poolToken, _isPaused);
    }
}
