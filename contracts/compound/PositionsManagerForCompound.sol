// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./positions-manager-parts/PositionsManagerForCompoundLogic.sol";

/// @title PositionsManagerForCompound.
/// @notice Smart contract interacting with Compound to enable P2P supply/borrow positions that can fallback on Compound's pool using pool tokens.
contract PositionsManagerForCompound is PositionsManagerForCompoundLogic {
    using MatchingEngineFns for IMatchingEngineForCompound;
    using DoubleLinkedList for DoubleLinkedList.List;
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;

    /// @notice Supplies underlying tokens in a specific market.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying) to supply.
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode
    ) external nonReentrant {
        marketsManager.updateP2PExchangeRates(_poolTokenAddress);
        _supply(_poolTokenAddress, _amount, maxGas.supply);

        emit Supplied(
            msg.sender,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
            _referralCode
        );
    }

    /// @notice Supplies underlying tokens in a specific market.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying) to supply.
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode,
        uint256 _maxGasToConsume
    ) external nonReentrant {
        marketsManager.updateP2PExchangeRates(_poolTokenAddress);
        _supply(_poolTokenAddress, _amount, _maxGasToConsume);

        emit Supplied(
            msg.sender,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
            _referralCode
        );
    }

    /// @notice Borrows underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode
    ) external nonReentrant {
        marketsManager.updateP2PExchangeRates(_poolTokenAddress);
        _borrow(_poolTokenAddress, _amount, maxGas.borrow);

        emit Borrowed(
            msg.sender,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
            _referralCode
        );
    }

    /// @notice Borrows underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode,
        uint256 _maxGasToConsume
    ) external nonReentrant {
        marketsManager.updateP2PExchangeRates(_poolTokenAddress);
        _borrow(_poolTokenAddress, _amount, _maxGasToConsume);

        emit Borrowed(
            msg.sender,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
            _referralCode
        );
    }

    /// @notice Withdraws underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of tokens (in underlying) to withdraw from supply.
    function withdraw(address _poolTokenAddress, uint256 _amount) external nonReentrant {
        marketsManager.updateP2PExchangeRates(_poolTokenAddress);

        uint256 toWithdraw = Math.min(
            _getUserSupplyBalanceInOf(_poolTokenAddress, msg.sender),
            _amount
        );

        _checkUserLiquidity(msg.sender, _poolTokenAddress, toWithdraw, 0);
        _withdraw(_poolTokenAddress, toWithdraw, msg.sender, msg.sender, maxGas.withdraw);
    }

    /// @notice Repays debt of the user.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying) to repay from borrow.
    function repay(address _poolTokenAddress, uint256 _amount) external nonReentrant {
        marketsManager.updateP2PExchangeRates(_poolTokenAddress);

        uint256 toRepay = Math.min(
            _getUserBorrowBalanceInOf(_poolTokenAddress, msg.sender),
            _amount
        );

        _repay(_poolTokenAddress, msg.sender, toRepay, maxGas.repay);
    }

    /// @notice Liquidates a position.
    /// @param _poolTokenBorrowedAddress The address of the pool token the liquidator wants to repay.
    /// @param _poolTokenCollateralAddress The address of the collateral pool token the liquidator wants to seize.
    /// @param _borrower The address of the borrower to liquidate.
    /// @param _amount The amount of token (in underlying) to repay.
    function liquidate(
        address _poolTokenBorrowedAddress,
        address _poolTokenCollateralAddress,
        address _borrower,
        uint256 _amount
    ) external nonReentrant {
        if (_amount == 0) revert AmountIsZero();
        marketsManager.updateP2PExchangeRates(_poolTokenCollateralAddress);
        marketsManager.updateP2PExchangeRates(_poolTokenBorrowedAddress);
        LiquidateVars memory vars;

        (vars.debtValue, vars.maxDebtValue) = _getUserHypotheticalBalanceStates(
            _borrower,
            address(0),
            0,
            0
        );
        if (vars.debtValue <= vars.maxDebtValue) revert DebtValueNotAboveMax();

        vars.borrowBalance = _getUserBorrowBalanceInOf(_poolTokenBorrowedAddress, _borrower);

        if (_amount > (vars.borrowBalance * LIQUIDATION_CLOSE_FACTOR_PERCENT) / MAX_BASIS_POINTS)
            revert AmountAboveWhatAllowedToRepay(); // Same mechanism as Compound. Liquidator cannot repay more than part of the debt (cf close factor on Compound).

        _repay(_poolTokenBorrowedAddress, _borrower, _amount, 0);

        // Calculate the amount of token to seize from collateral
        ICompoundOracle compoundOracle = ICompoundOracle(comptroller.oracle());
        vars.collateralPrice = compoundOracle.getUnderlyingPrice(_poolTokenCollateralAddress);
        vars.borrowedPrice = compoundOracle.getUnderlyingPrice(_poolTokenBorrowedAddress);
        if (vars.collateralPrice == 0 || vars.collateralPrice == 0) revert CompoundOracleFailed();

        // Get the exchange rate and calculate the number of collateral tokens to seize:
        // seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
        // seizeTokens = seizeAmount / exchangeRate
        // = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
        vars.amountToSeize = _amount
        .mul(comptroller.liquidationIncentiveMantissa())
        .mul(vars.borrowedPrice)
        .div(vars.collateralPrice);

        vars.supplyBalance = _getUserSupplyBalanceInOf(_poolTokenCollateralAddress, _borrower);

        if (vars.amountToSeize > vars.supplyBalance) revert ToSeizeAboveCollateral();

        _withdraw(_poolTokenCollateralAddress, vars.amountToSeize, _borrower, msg.sender, 0);

        emit Liquidated(
            msg.sender,
            _borrower,
            _amount,
            _poolTokenBorrowedAddress,
            vars.amountToSeize,
            _poolTokenCollateralAddress
        );
    }

    /// @dev Transfers the protocol reserve fee to the DAO.
    /// @param _poolTokenAddress The address of the market on which we want to claim the reserve fee.
    function claimToTreasury(address _poolTokenAddress)
        external
        onlyOwner
        isMarketCreatedAndNotPaused(_poolTokenAddress)
    {
        ERC20 underlyingToken = ERC20(ICToken(_poolTokenAddress).underlying());
        uint256 amountToClaim = underlyingToken.balanceOf(address(this));
        underlyingToken.safeTransfer(treasuryVault, amountToClaim);
        emit ReserveFeeClaimed(_poolTokenAddress, amountToClaim);
    }

    /// @notice Claims rewards for the given assets and the unclaimed rewards.
    /// @param _assets The assets to claim rewards from (aToken or variable debt token).
    /// @param _swap Whether or not to swap reward tokens for Morpho tokens.
    function claimRewards(address[] calldata _assets, bool _swap) external {
        // TODO: implement this function.
    }
}
