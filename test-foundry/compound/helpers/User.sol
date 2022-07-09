// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/compound/interfaces/IRewardsManager.sol";

import "@contracts/compound/Morpho.sol";
import "@contracts/compound/InterestRatesManager.sol";

contract User {
    using SafeTransferLib for ERC20;

    Morpho internal morpho;
    InterestRatesManager internal interestRatesManager;
    IRewardsManager internal rewardsManager;
    IComptroller internal comptroller;

    constructor(Morpho _morpho) {
        morpho = _morpho;
        interestRatesManager = InterestRatesManager(address(_morpho.interestRatesManager()));
        rewardsManager = _morpho.rewardsManager();
        comptroller = morpho.comptroller();
    }

    receive() external payable {}

    function compoundSupply(address _cTokenAddress, uint256 _amount) external {
        address[] memory marketToEnter = new address[](1);
        marketToEnter[0] = _cTokenAddress;
        comptroller.enterMarkets(marketToEnter);
        address underlying = ICToken(_cTokenAddress).underlying();
        ERC20(underlying).safeApprove(_cTokenAddress, type(uint256).max);
        require(ICToken(_cTokenAddress).mint(_amount) == 0, "Mint fail");
    }

    function compoundBorrow(address _cTokenAddress, uint256 _amount) external {
        require(ICToken(_cTokenAddress).borrow(_amount) == 0, "Borrow fail");
    }

    function compoundWithdraw(address _cTokenAddress, uint256 _amount) external {
        ICToken(_cTokenAddress).redeemUnderlying(_amount);
    }

    function compoundRepay(address _cTokenAddress, uint256 _amount) external {
        address underlying = ICToken(_cTokenAddress).underlying();
        ERC20(underlying).safeApprove(_cTokenAddress, type(uint256).max);
        ICToken(_cTokenAddress).repayBorrow(_amount);
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

    function claimRewards(address[] calldata _assets, bool _toSwap)
        external
        returns (uint256 claimedAmount)
    {
        return morpho.claimRewards(_assets, _toSwap);
    }

    function setP2PDisable(address _marketAddress, bool _newStatus) external {
        morpho.setP2PDisable(_marketAddress, _newStatus);
    }

    function setTreasuryVault(address _newTreasuryVault) external {
        morpho.setTreasuryVault(_newTreasuryVault);
    }

    function setPauseStatus(address _poolTokenAddress, bool _newStatus) external {
        morpho.setPauseStatus(_poolTokenAddress, _newStatus);
    }

    function setPartialPauseStatus(address _poolTokenAddress, bool _newStatus) external {
        morpho.setPartialPauseStatus(_poolTokenAddress, _newStatus);
    }
}
