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
    WithStorageAndModifiers,
    ReentrancyGuard
{
    using DoubleLinkedList for DoubleLinkedList.List;
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;

    /// STRUCTS ///

    // Struct to avoid stack too deep.
    struct LiquidateVars {
        uint256 debtValue;
        uint256 maxDebtValue;
        uint256 borrowBalance;
        uint256 supplyBalance;
        uint256 collateralPrice;
        uint256 borrowedPrice;
        uint256 amountToSeize;
    }

    /// EXTERNAL ///

    receive() external payable {}

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
        if (_amount == 0) revert AmountIsZero();
        LibMarketsManager.updateP2PExchangeRates(_poolTokenAddress);
        LibPositionsManager.supply(_poolTokenAddress, _amount, ps().maxGas.supply);

        emit Supplied(
            msg.sender,
            _poolTokenAddress,
            _amount,
            ps().supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            ps().supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
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
        if (_amount == 0) revert AmountIsZero();
        LibMarketsManager.updateP2PExchangeRates(_poolTokenAddress);
        LibPositionsManager.supply(_poolTokenAddress, _amount, _maxGasToConsume);

        emit Supplied(
            msg.sender,
            _poolTokenAddress,
            _amount,
            ps().supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            ps().supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
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
        if (_amount == 0) revert AmountIsZero();
        LibMarketsManager.updateP2PExchangeRates(_poolTokenAddress);
        LibPositionsManager.borrow(_poolTokenAddress, _amount, ps().maxGas.borrow);

        emit Borrowed(
            msg.sender,
            _poolTokenAddress,
            _amount,
            ps().borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            ps().borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
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
        if (_amount == 0) revert AmountIsZero();
        LibMarketsManager.updateP2PExchangeRates(_poolTokenAddress);
        LibPositionsManager.borrow(_poolTokenAddress, _amount, _maxGasToConsume);

        emit Borrowed(
            msg.sender,
            _poolTokenAddress,
            _amount,
            ps().borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            ps().borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P,
            _referralCode
        );
    }

    /// @notice Withdraws underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of tokens (in underlying) to withdraw from supply.
    function withdraw(address _poolTokenAddress, uint256 _amount) external nonReentrant {
        if (_amount == 0) revert AmountIsZero();
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
            ps().maxGas.withdraw
        );

        emit Withdrawn(
            msg.sender,
            _poolTokenAddress,
            _amount,
            ps().supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            ps().supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P
        );
    }

    /// @notice Repays debt of the user.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying) to repay from borrow.
    function repay(address _poolTokenAddress, uint256 _amount) external nonReentrant {
        if (_amount == 0) revert AmountIsZero();
        LibMarketsManager.updateP2PExchangeRates(_poolTokenAddress);

        uint256 toRepay = Math.min(
            LibPositionsManagerGetters.getUserBorrowBalanceInOf(_poolTokenAddress, msg.sender),
            _amount
        );

        LibPositionsManager.repay(_poolTokenAddress, msg.sender, toRepay, ps().maxGas.repay);

        emit Repaid(
            msg.sender,
            _poolTokenAddress,
            _amount,
            ps().borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            ps().borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P
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

        // Calculate the amount of token to seize from collateral
        ICompoundOracle compoundOracle = ICompoundOracle(ms().comptroller.oracle());
        vars.collateralPrice = compoundOracle.getUnderlyingPrice(_poolTokenCollateralAddress);
        vars.borrowedPrice = compoundOracle.getUnderlyingPrice(_poolTokenBorrowedAddress);
        if (vars.collateralPrice == 0 || vars.collateralPrice == 0) revert CompoundOracleFailed();

        // Get the exchange rate and calculate the number of collateral tokens to seize:
        // seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
        // seizeTokens = seizeAmount / exchangeRate
        // = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
        vars.amountToSeize = _amount
        .mul(ms().comptroller.liquidationIncentiveMantissa())
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

    /// @dev Transfers the protocol reserve fee to the DAO.
    /// @param _poolTokenAddress The address of the market on which we want to claim the reserve fee.
    function claimToTreasury(address _poolTokenAddress) external onlyOwner {
        if (!ms().isCreated[_poolTokenAddress]) revert MarketNotCreated();
        if (ps().paused[_poolTokenAddress]) revert MarketPaused();
        if (ps().treasuryVault == address(0)) revert ZeroAddress();

        ERC20 underlyingToken = LibPositionsManagerGetters.getUnderlying(_poolTokenAddress);
        uint256 amountToClaim = underlyingToken.balanceOf(address(this));

        if (amountToClaim == 0) revert AmountIsZero();

        underlyingToken.safeTransfer(ps().treasuryVault, amountToClaim);
        emit ReserveFeeClaimed(_poolTokenAddress, amountToClaim);
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
            ms().comptroller.claimComp(address(this), _cTokenAddresses);
            ERC20 comp = ERC20(ms().comptroller.getCompAddress());
            if (_claimMorphoToken) {
                comp.safeApprove(address(ps().incentivesVault), amountOfRewards);
                ps().incentivesVault.convertCompToMorphoTokens(msg.sender, amountOfRewards);
                emit RewardsClaimedAndConverted(msg.sender, amountOfRewards);
            } else {
                comp.safeTransfer(msg.sender, amountOfRewards);
                emit RewardsClaimed(msg.sender, amountOfRewards);
            }
        }
    }

    /// SETTERS ///

    /// @notice Sets `NDS`.
    /// @param _newNDS The new `NDS` value.
    function setNDS(uint8 _newNDS) external onlyOwner {
        ps().NDS = _newNDS;
        emit NDSSet(_newNDS);
    }

    /// @notice Sets `maxGas`.
    /// @param _maxGas The new `maxGas`.
    function setMaxGas(Types.MaxGas memory _maxGas) external onlyOwner {
        ps().maxGas = _maxGas;
        emit MaxGasSet(_maxGas);
    }

    /// @notice Sets the `treasuryVault`.
    /// @param _newTreasuryVaultAddress The address of the new `treasuryVault`.
    function setTreasuryVault(address _newTreasuryVaultAddress) external onlyOwner {
        ps().treasuryVault = _newTreasuryVaultAddress;
        emit TreasuryVaultSet(_newTreasuryVaultAddress);
    }

    /// @notice Sets the `incentivesVault`.
    /// @param _newIncentivesVault The address of the new `incentivesVault`.
    function setIncentivesVault(address _newIncentivesVault) external onlyOwner {
        ps().incentivesVault = IIncentivesVault(_newIncentivesVault);
        emit IncentivesVaultSet(_newIncentivesVault);
    }

    /// @notice Sets the `rewardsManager`.
    /// @param _rewardsManagerAddress The address of the `rewardsManager`.
    function setRewardsManager(address _rewardsManagerAddress) external onlyOwner {
        ps().rewardsManager = IRewardsManagerForCompound(_rewardsManagerAddress);
        emit RewardsManagerSet(_rewardsManagerAddress);
    }

    /// @notice Sets the pause status on a specific market in case of emergency.
    /// @param _poolTokenAddress The address of the market to pause/unpause.
    function setPauseStatus(address _poolTokenAddress) external onlyOwner {
        bool newPauseStatus = !ps().paused[_poolTokenAddress];
        ps().paused[_poolTokenAddress] = newPauseStatus;
        emit PauseStatusSet(_poolTokenAddress, newPauseStatus);
    }

    /// @notice Toggles the activation of COMP rewards.
    function toggleCompRewardsActivation() external onlyOwner {
        bool newCompRewardsActive = !ps().isCompRewardsActive;
        ps().isCompRewardsActive = newCompRewardsActive;
        emit CompRewardsActive(newCompRewardsActive);
    }

    /// GETTERS ///

    function supplyBalanceInOf(address _poolTokenAddress, address _user)
        external
        view
        returns (uint256 inP2P_, uint256 onPool_)
    {
        inP2P_ = ps().supplyBalanceInOf[_poolTokenAddress][_user].inP2P;
        onPool_ = ps().supplyBalanceInOf[_poolTokenAddress][_user].onPool;
    }

    function borrowBalanceInOf(address _poolTokenAddress, address _user)
        external
        view
        returns (uint256 inP2P_, uint256 onPool_)
    {
        inP2P_ = ps().borrowBalanceInOf[_poolTokenAddress][_user].inP2P;
        onPool_ = ps().borrowBalanceInOf[_poolTokenAddress][_user].onPool;
    }
}
