// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@contracts/aave/PositionsManagerForAave.sol";
import "@contracts/aave/MarketsManagerForAave.sol";
import "@contracts/aave/RewardsManager.sol";

contract User {
    PositionsManagerForAave internal positionsManager;
    MarketsManagerForAave internal marketsManager;
    RewardsManager internal rewardsManager;

    constructor(
        PositionsManagerForAave _positionsManager,
        MarketsManagerForAave _marketsManager,
        RewardsManager _rewardsManager
    ) {
        positionsManager = _positionsManager;
        marketsManager = _marketsManager;
        rewardsManager = _rewardsManager;
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

    function createMarket(address _underlyingTokenAddress, uint256 _threshold) external {
        marketsManager.createMarket(_underlyingTokenAddress, _threshold);
    }

    function supply(address _poolTokenAddress, uint256 _amount) external {
        IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS()).approve(
            address(positionsManager),
            _amount
        );
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
        IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS()).approve(
            address(positionsManager),
            _amount
        );
        positionsManager.repay(_poolTokenAddress, _amount);
    }

    function liquidate(
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address _borrower,
        uint256 _amount
    ) external {
        IERC20(IAToken(_poolTokenBorrowedAddress).UNDERLYING_ASSET_ADDRESS()).approve(
            address(positionsManager),
            _amount
        );
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

    function setMaxGas(PositionsManagerForAave.MaxGas memory _maxGas) external {
        positionsManager.setMaxGas(_maxGas);
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

    function setPauseStatus() external {
        positionsManager.setPauseStatus();
    }

    function setAaveIncentivesControllerOnRewardsManager(address _aaveIncentivesController)
        external
    {
        rewardsManager.setAaveIncentivesController(_aaveIncentivesController);
    }
}
