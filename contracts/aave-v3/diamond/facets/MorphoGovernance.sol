// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import {Modifiers} from "../abstract/Modifiers.sol";
import {Math, LibMarkets, LibIndexes, EventsAndErrors as E} from "../libraries/Libraries.sol";

contract MorphoGovernance is Modifiers {
    /// @notice Sets `maxSortedUsers`.
    /// @param _newMaxSortedUsers The new `maxSortedUsers` value.
    function setMaxSortedUsers(uint256 _newMaxSortedUsers) external onlyOwner {
        if (_newMaxSortedUsers == 0) revert E.MaxSortedUsersCannotBeZero();
        maxSortedUsers = _newMaxSortedUsers;
        emit E.MaxSortedUsersSet(_newMaxSortedUsers);
    }

    /// @notice Sets `defaultMaxGasForMatching`.
    /// @param _defaultMaxGasForMatching The new `defaultMaxGasForMatching`.
    function setDefaultMaxGasForMatching(Types.MaxGasForMatching memory _defaultMaxGasForMatching)
        external
        onlyOwner
    {
        g().defaultMaxGasForMatching = _defaultMaxGasForMatching;
        emit E.DefaultMaxGasForMatchingSet(_defaultMaxGasForMatching);
    }

    /// @notice Sets the `rewardsManager`.
    /// @param _rewardsManager The new `rewardsManager`.
    function setRewardsManager(IRewardsManager _rewardsManager) external onlyOwner {
        rewardsManager = _rewardsManager;
        emit E.RewardsManagerSet(address(_rewardsManager));
    }

    /// @notice Sets the `treasuryVault`.
    /// @param _treasuryVault The address of the new `treasuryVault`.
    function setTreasuryVault(address _treasuryVault) external onlyOwner {
        c().treasuryVault = _treasuryVault;
        emit E.TreasuryVaultSet(_treasuryVault);
    }

    /// @notice Sets the `rewardsController`.
    /// @param _rewardsController The address of the new `rewardsController`.
    function setRewardsController(address _rewardsController) external onlyOwner {
        c().rewardsController = IRewardsController(_rewardsController);
        emit E.RewardsControllerSet(_rewardsController);
    }

    /// @notice Sets the `incentivesVault`.
    /// @param _incentivesVault The new `incentivesVault`.
    function setIncentivesVault(IIncentivesVault _incentivesVault) external onlyOwner {
        c().incentivesVault = _incentivesVault;
        emit E.IncentivesVaultSet(address(_incentivesVault));
    }

    /// @notice Sets the `reserveFactor`.
    /// @param _poolToken The market on which to set the `_newReserveFactor`.
    /// @param _newReserveFactor The proportion of the interest earned by users sent to the DAO, in basis point.
    function setReserveFactor(address _poolToken, uint16 _newReserveFactor)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        if (_newReserveFactor > MAX_BASIS_POINTS) revert E.ExceedsMaxBasisPoints();
        LibIndexes.updateIndexes(_poolToken);

        m().market[_poolToken].reserveFactor = _newReserveFactor;
        emit ReserveFactorSet(_poolToken, _newReserveFactor);
    }

    /// @notice Sets a new peer-to-peer cursor.
    /// @param _poolToken The address of the market to update.
    /// @param _p2pIndexCursor The new peer-to-peer cursor.
    function setP2PIndexCursor(address _poolToken, uint16 _p2pIndexCursor)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        if (_p2pIndexCursor > MAX_BASIS_POINTS) revert E.ExceedsMaxBasisPoints();
        LibIndexes.updateIndexes(_poolToken);

        m().market[_poolToken].p2pIndexCursor = _p2pIndexCursor;
        emit E.P2PIndexCursorSet(_poolToken, _p2pIndexCursor);
    }

    /// @notice Sets `isSupplyPaused` for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setIsSupplyPaused(address _poolToken, bool _isPaused)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        m().market[_poolToken].isSupplyPaused = _isPaused;
        emit E.IsSupplyPausedSet(_poolToken, _isPaused);
    }

    /// @notice Sets `isBorrowPaused` for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setIsBorrowPaused(address _poolToken, bool _isPaused)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        m().market[_poolToken].isBorrowPaused = _isPaused;
        emit E.IsBorrowPausedSet(_poolToken, _isPaused);
    }

    /// @notice Sets `isWithdrawPaused` for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setIsWithdrawPaused(address _poolToken, bool _isPaused)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        m().market[_poolToken].isWithdrawPaused = _isPaused;
        emit E.IsWithdrawPausedSet(_poolToken, _isPaused);
    }

    /// @notice Sets `isRepayPaused` for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setIsRepayPaused(address _poolToken, bool _isPaused)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        m().market[_poolToken].isRepayPaused = _isPaused;
        emit E.IsRepayPausedSet(_poolToken, _isPaused);
    }

    /// @notice Sets `isLiquidateCollateralPaused` for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setIsLiquidateCollateralPaused(address _poolToken, bool _isPaused)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        m().market[_poolToken].isLiquidateCollateralPaused = _isPaused;
        emit E.IsLiquidateCollateralPausedSet(_poolToken, _isPaused);
    }

    /// @notice Sets `isLiquidateBorrowPaused` for a given market.
    /// @param _poolToken The address of the market to update.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setIsLiquidateBorrowPaused(address _poolToken, bool _isPaused)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        m().market[_poolToken].isLiquidateBorrowPaused = _isPaused;
        emit E.IsLiquidateBorrowPausedSet(_poolToken, _isPaused);
    }

    /// @notice Sets the pause status for all markets.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setIsPausedForAllMarkets(bool _isPaused) external onlyOwner {
        uint256 numberOfMarketsCreated = m().marketsCreated.length;

        for (uint256 i; i < numberOfMarketsCreated; ++i) {
            LibMarkets.setPauseStatus(m().marketsCreated[i], _isPaused);
        }
    }

    /// @notice Sets `isP2PDisabled` for a given market.
    /// @param _poolToken The address of the market of which to enable/disable peer-to-peer matching.
    /// @param _isP2PDisabled True to disable the peer-to-peer market.
    function setIsP2PDisabled(address _poolToken, bool _isP2PDisabled)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        m().market[_poolToken].isP2PDisabled = _isP2PDisabled;
        emit E.IsP2PDisabledSet(_poolToken, _isP2PDisabled);
    }

    /// @notice Sets `isClaimRewardsPaused`.
    /// @param _isPaused The new pause status, true to pause the mechanism.
    function setIsClaimRewardsPaused(bool _isPaused) external onlyOwner {
        g().isClaimRewardsPaused = _isPaused;
        emit E.IsClaimRewardsPausedSet(_isPaused);
    }

    /// @notice Sets a market's asset as collateral.
    /// @param _poolToken The address of the market to (un)set as collateral.
    /// @param _assetAsCollateral True to set the asset as collateral (True by default).
    function setAssetAsCollateral(address _poolToken, bool _assetAsCollateral)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        c().pool.setUserUseReserveAsCollateral(
            m().market[_poolToken].underlyingToken,
            _assetAsCollateral
        );
    }

    /// @notice Sets a market as deprecated (allows liquidation of every position on this market).
    /// @param _poolToken The address of the market to update.
    /// @param _isDeprecated The new deprecated status, true to deprecate the market.
    function setIsDeprecated(address _poolToken, bool _isDeprecated)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        m().market[_poolToken].isDeprecated = _isDeprecated;
        emit E.IsDeprecatedSet(_poolToken, _isDeprecated);
    }

    /// @notice Increases peer-to-peer deltas, to put some liquidity back on the pool.
    /// @dev The current Morpho supply on the pool might not be enough to borrow `_amount` before resuppling it.
    /// In this case, consider calling multiple times this function.
    /// @param _poolToken The address of the market on which to increase deltas.
    /// @param _amount The maximum amount to add to the deltas (in underlying).
    function increaseP2PDeltas(address _poolToken, uint256 _amount)
        external
        onlyOwner
        isMarketCreated(_poolToken)
    {
        LibIndexes.updateIndexes(_poolToken);
        LibMarkets.increaseP2PDeltasLogic(_poolToken, _amount);
    }

    /// @notice Transfers the protocol reserve fee to the DAO.
    /// @param _poolTokens The addresses of the pool token addresses on which to claim the reserve fee.
    /// @param _amounts The list of amounts of underlying tokens to claim on each market.
    function claimToTreasury(address[] calldata _poolTokens, uint256[] calldata _amounts)
        external
        onlyOwner
    {
        if (treasuryVault == address(0)) revert ZeroAddress();

        uint256 numberOfMarkets = _poolTokens.length;

        for (uint256 i; i < numberOfMarkets; ++i) {
            address poolToken = _poolTokens[i];

            Types.Market memory market = market[poolToken];
            if (!LibMarkets.isMarketCreated(_poolToken)) continue;

            ERC20 underlyingToken = ERC20(market.underlyingToken);
            uint256 underlyingBalance = underlyingToken.balanceOf(address(this));

            if (underlyingBalance == 0) continue;

            uint256 toClaim = Math.min(_amounts[i], underlyingBalance);

            underlyingToken.safeTransfer(treasuryVault, toClaim);
            emit ReserveFeeClaimed(poolToken, toClaim);
        }
    }

    /// @notice Creates a new market to borrow/supply in.
    /// @param _underlyingToken The underlying token address.
    /// @param _reserveFactor The reserve factor to set on this market.
    /// @param _p2pIndexCursor The peer-to-peer index cursor to set on this market.
    function createMarket(
        address _underlyingToken,
        uint16 _reserveFactor,
        uint16 _p2pIndexCursor
    ) external onlyOwner {
        if (marketsCreated.length >= MAX_NB_OF_MARKETS) revert MaxNumberOfMarkets();
        if (_underlyingToken == address(0)) revert ZeroAddress();
        if (_p2pIndexCursor > MAX_BASIS_POINTS || _reserveFactor > MAX_BASIS_POINTS)
            revert ExceedsMaxBasisPoints();

        if (!pool.getConfiguration(_underlyingToken).getActive()) revert MarketIsNotListedOnAave();

        address poolToken = pool.getReserveData(_underlyingToken).aTokenAddress;

        if (market[poolToken].isCreated()) revert MarketAlreadyCreated();

        p2pSupplyIndex[poolToken] = WadRayMath.RAY;
        p2pBorrowIndex[poolToken] = WadRayMath.RAY;

        Types.PoolIndexes storage poolIndexes = poolIndexes[poolToken];

        poolIndexes.lastUpdateTimestamp = uint32(block.timestamp);
        poolIndexes.poolSupplyIndex = uint112(pool.getReserveNormalizedIncome(_underlyingToken));
        poolIndexes.poolBorrowIndex = uint112(
            pool.getReserveNormalizedVariableDebt(_underlyingToken)
        );

        market[poolToken] = Types.Market({
            underlyingToken: _underlyingToken,
            reserveFactor: _reserveFactor,
            p2pIndexCursor: _p2pIndexCursor,
            isSupplyPaused: false,
            isBorrowPaused: false,
            isP2PDisabled: false,
            isWithdrawPaused: false,
            isRepayPaused: false,
            isLiquidateCollateralPaused: false,
            isLiquidateBorrowPaused: false,
            isDeprecated: false
        });

        borrowMask[poolToken] = ONE << (marketsCreated.length << 1);
        marketsCreated.push(poolToken);

        ERC20(_underlyingToken).safeApprove(address(pool), type(uint256).max);

        emit MarketCreated(poolToken, _reserveFactor, _p2pIndexCursor);
    }

    /// INTERNAL ///
}
