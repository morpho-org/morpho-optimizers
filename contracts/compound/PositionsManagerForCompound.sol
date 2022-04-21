// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./libraries/LibPositionsManager.sol";
import "./libraries/LibMarketsManager.sol";
import "./libraries/CompoundMath.sol";
import "./libraries/LibStorage.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./PositionsManagerForCompoundEventsErrors.sol";

/// @title PositionsManagerForCompound.
/// @notice Smart contract interacting with Compound to enable P2P supply/borrow positions that can fallback on Compound's pool using pool tokens.
contract PositionsManagerForCompound is
    PositionsManagerForCompoundEventsErrors,
    WithStorageAndModifiers
{
    using DoubleLinkedList for DoubleLinkedList.List;
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;

    /// STRUCTS ///

    // Struct to avoid stack too deep.
    struct LiquidateVars {
        uint256 collateralPrice;
        uint256 supplyBalance;
        uint256 borrowBalance;
        uint256 borrowedPrice;
        uint256 amountToSeize;
        uint256 maxDebtValue;
        uint256 debtValue;
    }

    /// EXTERNAL ///

    /// @notice Allows to receive ETH.
    receive() external payable {}

    /// @notice Supplies underlying tokens in a specific market.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying) to supply.
    function supply(address _poolTokenAddress, uint256 _amount) external nonReentrant {
        if (_amount == 0) revert AmountIsZero();
        PositionsStorage storage p = ps();

        LibMarketsManager.updateP2PExchangeRates(_poolTokenAddress);
        LibPositionsManager.supply(_poolTokenAddress, _amount, p.maxGas.supply);

        emit Supplied(
            msg.sender,
            _poolTokenAddress,
            _amount,
            p.supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            p.supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P
        );
    }

    /// @notice Supplies underlying tokens in a specific market.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying) to supply.
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) external nonReentrant {
        if (_amount == 0) revert AmountIsZero();
        PositionsStorage storage p = ps();

        LibMarketsManager.updateP2PExchangeRates(_poolTokenAddress);
        LibPositionsManager.supply(_poolTokenAddress, _amount, _maxGasToConsume);

        emit Supplied(
            msg.sender,
            _poolTokenAddress,
            _amount,
            p.supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            p.supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P
        );
    }

    /// @notice Borrows underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    function borrow(address _poolTokenAddress, uint256 _amount) external nonReentrant {
        if (_amount == 0) revert AmountIsZero();
        PositionsStorage storage p = ps();

        LibMarketsManager.updateP2PExchangeRates(_poolTokenAddress);
        LibPositionsManager.borrow(_poolTokenAddress, _amount, p.maxGas.borrow);

        emit Borrowed(
            msg.sender,
            _poolTokenAddress,
            _amount,
            p.borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            p.borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P
        );
    }

    /// @notice Borrows underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) external nonReentrant {
        if (_amount == 0) revert AmountIsZero();
        PositionsStorage storage p = ps();

        LibMarketsManager.updateP2PExchangeRates(_poolTokenAddress);
        LibPositionsManager.borrow(_poolTokenAddress, _amount, _maxGasToConsume);

        emit Borrowed(
            msg.sender,
            _poolTokenAddress,
            _amount,
            p.borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            p.borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P
        );
    }

    /// @notice Withdraws underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of tokens (in underlying) to withdraw from supply.
    function withdraw(address _poolTokenAddress, uint256 _amount) external nonReentrant {
        if (_amount == 0) revert AmountIsZero();
        PositionsStorage storage p = ps();

        LibMarketsManager.updateP2PExchangeRates(_poolTokenAddress);
        uint256 toWithdraw = Math.min(
            LibPositionsManagerGetters.getUserSupplyBalanceInOf(_poolTokenAddress, msg.sender),
            _amount
        );
        LibPositionsManager.checkUserLiquidity(msg.sender, _poolTokenAddress, toWithdraw, 0);
        LibPositionsManager.withdraw(
            _poolTokenAddress,
            toWithdraw,
            msg.sender,
            msg.sender,
            p.maxGas.withdraw
        );

        emit Withdrawn(
            msg.sender,
            _poolTokenAddress,
            toWithdraw,
            p.supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            p.supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P
        );
    }

    /// @notice Repays debt of the user.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying) to repay from borrow.
    function repay(address _poolTokenAddress, uint256 _amount) external nonReentrant {
        if (_amount == 0) revert AmountIsZero();
        PositionsStorage storage p = ps();

        LibMarketsManager.updateP2PExchangeRates(_poolTokenAddress);
        uint256 toRepay = Math.min(
            LibPositionsManagerGetters.getUserBorrowBalanceInOf(_poolTokenAddress, msg.sender),
            _amount
        );
        LibPositionsManager.repay(_poolTokenAddress, msg.sender, toRepay, p.maxGas.repay);

        emit Repaid(
            msg.sender,
            _poolTokenAddress,
            toRepay,
            p.borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            p.borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P
        );
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
        LibMarketsManager.updateP2PExchangeRates(_poolTokenBorrowedAddress);
        LibMarketsManager.updateP2PExchangeRates(_poolTokenCollateralAddress);
        LiquidateVars memory vars;

        (vars.debtValue, vars.maxDebtValue) = LibPositionsManagerGetters
        .getUserHypotheticalBalanceStates(_borrower, address(0), 0, 0);
        if (vars.debtValue <= vars.maxDebtValue) revert DebtValueNotAboveMax();

        vars.borrowBalance = LibPositionsManagerGetters.getUserBorrowBalanceInOf(
            _poolTokenBorrowedAddress,
            _borrower
        );

        if (_amount > (vars.borrowBalance * LIQUIDATION_CLOSE_FACTOR_PERCENT) / MAX_BASIS_POINTS)
            revert AmountAboveWhatAllowedToRepay(); // Same mechanism as Compound. Liquidator cannot repay more than part of the debt (cf close factor on Compound).

        LibPositionsManager.repay(_poolTokenBorrowedAddress, _borrower, _amount, 0);

        PositionsStorage storage p = ps();

        // Calculate the amount of token to seize from collateral
        ICompoundOracle compoundOracle = ICompoundOracle(p.comptroller.oracle());
        vars.collateralPrice = compoundOracle.getUnderlyingPrice(_poolTokenCollateralAddress);
        vars.borrowedPrice = compoundOracle.getUnderlyingPrice(_poolTokenBorrowedAddress);
        if (vars.collateralPrice == 0 || vars.borrowedPrice == 0) revert CompoundOracleFailed();

        // Get the exchange rate and calculate the number of collateral tokens to seize:
        // seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
        // seizeTokens = seizeAmount / exchangeRate
        // = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
        vars.amountToSeize = _amount
        .mul(p.comptroller.liquidationIncentiveMantissa())
        .mul(vars.borrowedPrice)
        .div(vars.collateralPrice);

        vars.supplyBalance = LibPositionsManagerGetters.getUserSupplyBalanceInOf(
            _poolTokenCollateralAddress,
            _borrower
        );

        if (vars.amountToSeize > vars.supplyBalance) revert ToSeizeAboveCollateral();

        LibPositionsManager.withdraw(
            _poolTokenCollateralAddress,
            vars.amountToSeize,
            _borrower,
            msg.sender,
            0
        );

        emit Liquidated(
            msg.sender,
            _borrower,
            _amount,
            _poolTokenBorrowedAddress,
            vars.amountToSeize,
            _poolTokenCollateralAddress
        );
    }

    /// @notice Claims rewards for the given assets and the unclaimed rewards.
    /// @param _claimMorphoToken Whether or not to claim Morpho tokens instead of token reward.
    function claimRewards(address[] calldata _cTokenAddresses, bool _claimMorphoToken)
        external
        nonReentrant
    {
        uint256 amountOfRewards = ps().rewardsManager.claimRewards(_cTokenAddresses, msg.sender);

        if (amountOfRewards == 0) revert AmountIsZero();
        else {
            PositionsStorage storage p = ps();
            p.comptroller.claimComp(address(this), _cTokenAddresses);
            ERC20 comp = ERC20(p.comptroller.getCompAddress());
            if (_claimMorphoToken) {
                comp.safeApprove(address(p.incentivesVault), amountOfRewards);
                p.incentivesVault.convertCompToMorphoTokens(msg.sender, amountOfRewards);
                emit RewardsClaimedAndConverted(msg.sender, amountOfRewards);
            } else {
                comp.safeTransfer(msg.sender, amountOfRewards);
                emit RewardsClaimed(msg.sender, amountOfRewards);
            }
        }
    }
}
