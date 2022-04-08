// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/compound/interfaces/IRewardsManagerForCompound.sol";

import "@contracts/compound/PositionsManagerForCompound.sol";
import "@contracts/compound/MarketsManagerForCompound.sol";

contract User {
    using SafeTransferLib for ERC20;

    PositionsManagerForCompound internal positionsManager;
    MarketsManagerForCompound internal marketsManager;
    IRewardsManagerForCompound internal rewardsManager;

    constructor(PositionsManagerForCompound _positionsManager) {
        positionsManager = _positionsManager;
        marketsManager = MarketsManagerForCompound(address(_positionsManager.marketsManager()));
        rewardsManager = _positionsManager.rewardsManager();
    }

    receive() external payable {}

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

    function updateRates(address _marketAddress) external {
        marketsManager.updateRates(_marketAddress);
    }

    function supply(address _poolTokenAddress, uint256 _amount) external {
        positionsManager.supply(_poolTokenAddress, _amount, 0);
    }

    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) external {
        positionsManager.supply(_poolTokenAddress, _amount, 0, _maxGasToConsume);
    }

    function withdraw(address _poolTokenAddress, uint256 _amount) external {
        positionsManager.withdraw(_poolTokenAddress, _amount);
    }

    function borrow(address _poolTokenAddress, uint256 _amount) external {
        positionsManager.borrow(_poolTokenAddress, _amount, 0);
    }

    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) external {
        positionsManager.borrow(_poolTokenAddress, _amount, 0, _maxGasToConsume);
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

    function setMaxGas(PositionsManagerForCompound.MaxGas memory _maxGas) external {
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
