// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@contracts/aave-v3/interfaces/IRewardsManager.sol";

import "@contracts/aave-v3/Morpho.sol";
import "@forge-std/Test.sol";

contract User is Test {
    using SafeTransferLib for ERC20;

    Vm public hevm = Vm(HEVM_ADDRESS);
    Morpho internal morpho;
    IRewardsManager internal rewardsManager;
    IPool public pool;
    IRewardsController public rewardsController;

    uint256 tm = 1;

    constructor(Morpho _morpho) {
        setMorphoAddresses(_morpho);
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

    function supply(address _poolToken, uint256 _amount) external {
        hevm.warp(block.timestamp + tm);
        morpho.supply(_poolToken, _amount);
    }

    function supply(
        address _poolToken,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external {
        hevm.warp(block.timestamp + tm);
        morpho.supply(_poolToken, address(this), _amount, _maxGasForMatching);
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
        hevm.warp(block.timestamp + tm);
        morpho.repay(_poolToken, _amount);
    }

    function aaveSupply(address _underlyingTokenAddress, uint256 _amount) external {
        hevm.warp(block.timestamp + tm);
        ERC20(_underlyingTokenAddress).safeApprove(address(pool), type(uint256).max);
        pool.supply(_underlyingTokenAddress, _amount, address(this), 0); // 0 : no refferal code
    }

    function aaveBorrow(address _underlyingTokenAddress, uint256 _amount) external {
        pool.borrow(_underlyingTokenAddress, _amount, 2, 0, address(this)); // 2 : variable rate | 0 : no refferal code
    }

    function aaveClaimRewards(address[] memory _assets) external {
        rewardsController.claimAllRewardsToSelf(_assets);
    }

    function liquidate(
        address _poolTokenBorrowed,
        address _poolTokenCollateral,
        address _borrower,
        uint256 _amount
    ) external {
        hevm.warp(block.timestamp + tm);
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

    function claimRewards(address[] calldata _assets, bool _tradeForMorphoToken)
        external
        returns (address[] memory rewardTokens, uint256[] memory claimedAmounts)
    {
        return morpho.claimRewards(_assets, _tradeForMorphoToken);
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

    function setMorphoAddresses(Morpho _morpho) public {
        morpho = _morpho;
        rewardsManager = _morpho.rewardsManager();
        pool = _morpho.pool();
        rewardsController = _morpho.rewardsController();
    }
}
