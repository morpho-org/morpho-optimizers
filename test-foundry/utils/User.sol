// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@contracts/aave/PositionsManagerForAave.sol";
import "@contracts/aave/MarketsManagerForAave.sol";
import "@contracts/aave/interfaces/IRewardsManagerForAave.sol";

contract User {
    using SafeTransferLib for ERC20;

    PositionsManagerForAave internal positionsManager;
    MarketsManagerForAave internal marketsManager;
    IRewardsManagerForAave internal rewardsManager;
    ILendingPool public lendingPool;
    IAaveIncentivesController public aaveIncentivesController;

    constructor(
        PositionsManagerForAave _positionsManager,
        MarketsManagerForAave _marketsManager,
        IRewardsManagerForAave _rewardsManager
    ) {
        positionsManager = _positionsManager;
        marketsManager = _marketsManager;
        rewardsManager = _rewardsManager;
        lendingPool = positionsManager.lendingPool();
        aaveIncentivesController = positionsManager.aaveIncentivesController();
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

    function createMarket(address _underlyingTokenAddress, uint256 _threshold) external {
        marketsManager.createMarket(_underlyingTokenAddress, _threshold);
    }

    function setThreshold(address _marketAddress, uint256 _threshold) external {
        marketsManager.setThreshold(_marketAddress, _threshold);
    }

    function setReserveFactor(uint16 _threshold) external {
        marketsManager.setReserveFactor(_threshold);
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

    function aaveSupply(address _underlyingTokenAddress, uint256 _amount) external {
        ERC20(_underlyingTokenAddress).safeApprove(address(lendingPool), type(uint256).max);
        lendingPool.deposit(_underlyingTokenAddress, _amount, address(this), 0); // 0 : no refferal code
    }

    function aaveBorrow(address _underlyingTokenAddress, uint256 _amount) external {
        lendingPool.borrow(_underlyingTokenAddress, _amount, 2, 0, address(this)); // 2 : variable rate | 0 : no refferal code
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

    function setAaveIncentivesControllerOnRewardsManager(address _aaveIncentivesController)
        external
    {
        rewardsManager.setAaveIncentivesController(_aaveIncentivesController);
    }
}
