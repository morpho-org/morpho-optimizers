// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "src/compound/interfaces/IRewardsManager.sol";

import "src/compound/Morpho.sol";

contract User {
    using SafeTransferLib for ERC20;

    Morpho internal morpho;
    IRewardsManager internal rewardsManager;
    IComptroller internal comptroller;

    constructor(Morpho _morpho) {
        morpho = _morpho;
        rewardsManager = _morpho.rewardsManager();
        comptroller = morpho.comptroller();
    }

    receive() external payable {}

    function compoundSupply(address _poolToken, uint256 _amount) external {
        address[] memory marketToEnter = new address[](1);
        marketToEnter[0] = _poolToken;
        comptroller.enterMarkets(marketToEnter);
        address underlying = ICToken(_poolToken).underlying();
        ERC20(underlying).safeApprove(_poolToken, type(uint256).max);
        require(ICToken(_poolToken).mint(_amount) == 0, "Mint fail");
    }

    function compoundBorrow(address _poolToken, uint256 _amount) external {
        require(ICToken(_poolToken).borrow(_amount) == 0, "Borrow fail");
    }

    function compoundWithdraw(address _poolToken, uint256 _amount) external {
        ICToken(_poolToken).redeemUnderlying(_amount);
    }

    function compoundRepay(address _poolToken, uint256 _amount) external {
        address underlying = ICToken(_poolToken).underlying();
        ERC20(underlying).safeApprove(_poolToken, type(uint256).max);
        ICToken(_poolToken).repayBorrow(_amount);
    }

    function compoundClaimRewards(address[] memory assets) external {
        comptroller.claimComp(address(this), assets);
    }

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

    function createMarket(address _underlyingToken, Types.MarketParameters calldata _marketParams)
        external
    {
        morpho.createMarket(_underlyingToken, _marketParams);
    }

    function setReserveFactor(address _poolToken, uint16 _reserveFactor) external {
        morpho.setReserveFactor(_poolToken, _reserveFactor);
    }

    function supply(address _poolToken, uint256 _amount) external {
        morpho.supply(_poolToken, _amount);
    }

    function supply(
        address _poolToken,
        address _onBehalf,
        uint256 _amount
    ) public {
        morpho.supply(_poolToken, _onBehalf, _amount);
    }

    function supply(
        address _poolToken,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) public {
        morpho.supply(_poolToken, _onBehalf, _amount, _maxGasForMatching);
    }

    function supply(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external {
        supply(_poolToken, address(this), _amount, _maxGasForMatching);
    }

    function borrow(address _poolToken, uint256 _amount) external {
        morpho.borrow(_poolToken, _amount);
    }

    function borrow(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external {
        morpho.borrow(_poolToken, _amount, _maxGasForMatching);
    }

    function withdraw(address _poolToken, uint256 _amount) external {
        morpho.withdraw(_poolToken, _amount);
    }

    function withdraw(
        address _poolToken,
        uint256 _amount,
        address _receiver
    ) external {
        morpho.withdraw(_poolToken, _amount, _receiver);
    }

    function repay(address _poolToken, uint256 _amount) external {
        morpho.repay(_poolToken, _amount);
    }

    function repay(
        address _poolToken,
        address _onBehalf,
        uint256 _amount
    ) public {
        morpho.repay(_poolToken, _onBehalf, _amount);
    }

    function liquidate(
        address _poolTokenBorrowed,
        address _poolTokenCollateral,
        address _borrower,
        uint256 _amount
    ) external {
        morpho.liquidate(_poolTokenBorrowed, _poolTokenCollateral, _borrower, _amount);
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

    function setIsP2PDisabled(address _market, bool _isPaused) external {
        morpho.setIsP2PDisabled(_market, _isPaused);
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
