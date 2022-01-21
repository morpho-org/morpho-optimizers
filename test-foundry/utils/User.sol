// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@contracts/aave/PositionsManagerForAave.sol";
import "@contracts/aave/MarketsManagerForAave.sol";

contract User {
    PositionsManagerForAave internal positionsManager;
    MarketsManagerForAave internal marketsManager;

    constructor(PositionsManagerForAave _positionsManager, MarketsManagerForAave _marketsManager) {
        positionsManager = _positionsManager;
        marketsManager = _marketsManager;
    }

    receive() external payable {}

    function balanceOf(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    function approve(address _token, uint256 _amount) external {
        IERC20(_token).approve(address(positionsManager), _amount);
    }

    function approve(
        address _token,
        address _spender,
        uint256 _amount
    ) external {
        IERC20(_token).approve(_spender, _amount);
    }

    function createMarket(
        address _marketAddress,
        uint256 _threshold,
        uint256 _capValue
    ) external {
        marketsManager.createMarket(_marketAddress, _threshold, _capValue);
    }

    function setCapValue(address _marketAddress, uint256 _newCapValue) external {
        marketsManager.setCapValue(_marketAddress, _newCapValue);
    }

    function supply(address _poolTokenAddress, uint256 _amount) external {
        positionsManager.supply(_poolTokenAddress, _amount, 0);
    }

    function withdraw(address _poolTokenAddress, uint256 _amount) external {
        positionsManager.withdraw(_poolTokenAddress, _amount);
    }

    function borrow(address _poolTokenAddress, uint256 _amount) external {
        positionsManager.borrow(_poolTokenAddress, _amount, 0);
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

    function setNmaxForMatchingEngine(uint16 _newMaxNumber) external {
        positionsManager.setNmaxForMatchingEngine(_newMaxNumber);
    }

    function claimRewards(address[] calldata _assets) external {
        positionsManager.claimRewards(_assets);
    }

    function setNoP2P(address _marketAddress, bool _noP2P) external {
        marketsManager.setNoP2P(_marketAddress, _noP2P);
    }

    function setTreasuryVault(address _newTreasuryVault) external {
        positionsManager.setTreasuryVault(_newTreasuryVault);
    }
}
