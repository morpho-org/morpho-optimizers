// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/compound/interfaces/IRewardsManager.sol";

import "@contracts/compound/PositionsManager.sol";
import "@contracts/compound/MarketsManager.sol";

contract User {
    using SafeTransferLib for ERC20;

    PositionsManager internal positionsManager;
    MarketsManager internal marketsManager;
    IRewardsManager internal rewardsManager;
    IComptroller internal comptroller;

    constructor(PositionsManager _positionsManager) {
        positionsManager = _positionsManager;
        marketsManager = MarketsManager(address(_positionsManager.MARKETS_MANAGER()));
        rewardsManager = _positionsManager.rewardsManager();
        comptroller = positionsManager.COMPTROLLER();
    }

    receive() external payable {}

    function compoundSupply(address _cTokenAddress, uint256 _amount) external {
        address underlying = ICToken(_cTokenAddress).underlying();
        ERC20(underlying).safeApprove(_cTokenAddress, type(uint256).max);
        ICToken(_cTokenAddress).mint(_amount);
    }

    function compoundBorrow(address _cTokenAddress, uint256 _amount) external {
        ICToken(_cTokenAddress).borrow(_amount);
    }

    function compoundClaimRewards(address[] memory assets) external {
        comptroller.claimComp(address(this), assets);
    }

    function balanceOf(address _token) external view returns (uint256) {
        return ERC20(_token).balanceOf(address(this));
    }

    function approve(address _token, uint256 _amount) external {
        ERC20(_token).safeApprove(address(positionsManager), _amount);
    }

    function approve(
        address _token,
        address _spender,
        uint256 _amount
    ) external {
        ERC20(_token).safeApprove(_spender, _amount);
    }

    function createMarket(address _underlyingTokenAddress) external {
        marketsManager.createMarket(_underlyingTokenAddress);
    }

    function setReserveFactor(address _poolTokenAddress, uint16 _reserveFactor) external {
        marketsManager.setReserveFactor(_poolTokenAddress, _reserveFactor);
    }

    function supply(address _poolTokenAddress, uint256 _amount) external {
        positionsManager.supply(_poolTokenAddress, _amount);
    }

    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) external {
        positionsManager.supply(_poolTokenAddress, _amount, _maxGasToConsume);
    }

    function withdraw(address _poolTokenAddress, uint256 _amount) external {
        positionsManager.withdraw(_poolTokenAddress, _amount);
    }

    function borrow(address _poolTokenAddress, uint256 _amount) external {
        positionsManager.borrow(_poolTokenAddress, _amount);
    }

    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) external {
        positionsManager.borrow(_poolTokenAddress, _amount, _maxGasToConsume);
    }

    function repay(address _poolTokenAddress, uint256 _amount) external {
        positionsManager.repay(_poolTokenAddress, _amount);
    }

    function liquidate(
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address _borrower,
        uint256 _amount
    ) external {
        positionsManager.liquidate(
            _poolTokenBorrowedAddress,
            _poolTokenCollateralAddress,
            _borrower,
            _amount
        );
    }

    function setNDS(uint8 _newNDS) external {
        positionsManager.setNDS(_newNDS);
    }

    function setMaxGas(PositionsManager.MaxGas memory _maxGas) external {
        positionsManager.setMaxGas(_maxGas);
    }

    function claimRewards(address[] calldata _assets, bool _toSwap) external {
        positionsManager.claimRewards(_assets, _toSwap);
    }

    function setNoP2P(address _marketAddress, bool _noP2P) external {
        marketsManager.setNoP2P(_marketAddress, _noP2P);
    }

    function setTreasuryVault(address _newTreasuryVault) external {
        positionsManager.setTreasuryVault(_newTreasuryVault);
    }

    function setPauseStatus(address _poolTokenAddress) external {
        positionsManager.setPauseStatus(_poolTokenAddress);
    }
}
