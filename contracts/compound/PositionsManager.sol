// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./positions-manager-parts/PositionsManagerSetters.sol";
import "./libraries/LogicDCs.sol";

/// @title PositionsManager.
/// @notice Smart contract interacting with Compound to enable P2P supply/borrow positions that can fallback on Compound's pool using pool tokens.
contract PositionsManager is PositionsManagerSetters {
    using LogicDCs for ILogic;
    using DoubleLinkedList for DoubleLinkedList.List;
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;

    /// UPGRADE ///

    /// @notice Initializes the PositionsManager contract.
    /// @param _marketsManager The `marketsManager`.
    /// @param _comptroller The `comptroller`.
    /// @param _maxGas The `maxGas`.
    /// @param _NDS The `NDS`.
    /// @param _cEth The cETH address.
    /// @param _weth The wETH address.
    function initialize(
        IMarketsManager _marketsManager,
        ILogic _logic,
        IComptroller _comptroller,
        MaxGas memory _maxGas,
        uint8 _NDS,
        address _cEth,
        address _weth
    ) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();

        marketsManager = _marketsManager;
        logic = _logic;
        comptroller = _comptroller;

        maxGas = _maxGas;
        NDS = _NDS;

        cEth = _cEth;
        wEth = _weth;
    }

    /// @notice Supplies underlying tokens in a specific market.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying) to supply.
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode
    ) external nonReentrant isMarketCreatedAndNotPaused(_poolTokenAddress) {
        if (_amount == 0) revert AmountIsZero();
        marketsManager.updateP2PExchangeRates(_poolTokenAddress);

        logic._supplyDC(_poolTokenAddress, _amount, maxGas.supply);

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
    ) external nonReentrant isMarketCreatedAndNotPaused(_poolTokenAddress) {
        if (_amount == 0) revert AmountIsZero();
        marketsManager.updateP2PExchangeRates(_poolTokenAddress);

        logic._supplyDC(_poolTokenAddress, _amount, _maxGasToConsume);

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
    ) external nonReentrant isMarketCreatedAndNotPaused(_poolTokenAddress) {
        if (_amount == 0) revert AmountIsZero();
        marketsManager.updateP2PExchangeRates(_poolTokenAddress);

        logic._borrowDC(_poolTokenAddress, _amount, maxGas.borrow);

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
    ) external nonReentrant isMarketCreatedAndNotPaused(_poolTokenAddress) {
        if (_amount == 0) revert AmountIsZero();
        marketsManager.updateP2PExchangeRates(_poolTokenAddress);

        logic._borrowDC(_poolTokenAddress, _amount, _maxGasToConsume);

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
    function withdraw(address _poolTokenAddress, uint256 _amount)
        external
        nonReentrant
        isMarketCreatedAndNotPaused(_poolTokenAddress)
    {
        if (_amount == 0) revert AmountIsZero();
        marketsManager.updateP2PExchangeRates(_poolTokenAddress);

        uint256 toWithdraw = Math.min(
            _getUserSupplyBalanceInOf(_poolTokenAddress, msg.sender),
            _amount
        );

        _checkUserLiquidity(msg.sender, _poolTokenAddress, toWithdraw, 0);
        logic._withdrawDC(_poolTokenAddress, toWithdraw, msg.sender, msg.sender, maxGas.withdraw);

        emit Withdrawn(
            msg.sender,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P
        );
    }

    /// @notice Repays debt of the user.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying) to repay from borrow.
    function repay(address _poolTokenAddress, uint256 _amount)
        external
        nonReentrant
        isMarketCreatedAndNotPaused(_poolTokenAddress)
    {
        if (_amount == 0) revert AmountIsZero();
        marketsManager.updateP2PExchangeRates(_poolTokenAddress);

        uint256 toRepay = Math.min(
            _getUserBorrowBalanceInOf(_poolTokenAddress, msg.sender),
            _amount
        );

        logic._repayDC(_poolTokenAddress, msg.sender, toRepay, maxGas.repay);

        emit Repaid(
            msg.sender,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P
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
    )
        external
        nonReentrant
        isMarketCreatedAndNotPaused(_poolTokenBorrowedAddress)
        isMarketCreatedAndNotPaused(_poolTokenCollateralAddress)
    {
        if (_amount == 0) revert AmountIsZero();
        marketsManager.updateP2PExchangeRates(_poolTokenBorrowedAddress);
        marketsManager.updateP2PExchangeRates(_poolTokenCollateralAddress);

        uint256 amountSeized = logic._liquidateDC(
            _poolTokenBorrowedAddress,
            _poolTokenCollateralAddress,
            _borrower,
            _amount
        );

        emit Liquidated(
            msg.sender,
            _borrower,
            _amount,
            _poolTokenBorrowedAddress,
            amountSeized,
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
        if (treasuryVault == address(0)) revert ZeroAddress();

        ERC20 underlyingToken = _getUnderlying(_poolTokenAddress);
        uint256 amountToClaim = underlyingToken.balanceOf(address(this));

        if (amountToClaim == 0) revert AmountIsZero();

        underlyingToken.safeTransfer(treasuryVault, amountToClaim);
        emit ReserveFeeClaimed(_poolTokenAddress, amountToClaim);
    }

    /// @notice Claims rewards for the given assets and the unclaimed rewards.
    /// @param _claimMorphoToken Whether or not to claim Morpho tokens instead of token reward.
    function claimRewards(address[] calldata _cTokenAddresses, bool _claimMorphoToken)
        external
        nonReentrant
    {
        uint256 amountOfRewards = rewardsManager.claimRewards(_cTokenAddresses, msg.sender);

        if (amountOfRewards == 0) revert AmountIsZero();
        else {
            comptroller.claimComp(address(this), _cTokenAddresses);
            ERC20 comp = ERC20(comptroller.getCompAddress());
            if (_claimMorphoToken) {
                comp.safeApprove(address(incentivesVault), amountOfRewards);
                incentivesVault.convertCompToMorphoTokens(msg.sender, amountOfRewards);
                emit RewardsClaimedAndConverted(msg.sender, amountOfRewards);
            } else {
                comp.safeTransfer(msg.sender, amountOfRewards);
                emit RewardsClaimed(msg.sender, amountOfRewards);
            }
        }
    }

    /// GETTERS

    /// @notice Gets the head of the data structure on a specific market (for UI).
    /// @param _poolTokenAddress The address of the market from which to get the head.
    /// @param _positionType The type of user from which to get the head.
    /// @return head The head in the data structure.
    function getHead(address _poolTokenAddress, PositionType _positionType)
        external
        view
        returns (address head)
    {
        if (_positionType == PositionType.SUPPLIERS_IN_P2P)
            head = suppliersInP2P[_poolTokenAddress].getHead();
        else if (_positionType == PositionType.SUPPLIERS_ON_POOL)
            head = suppliersOnPool[_poolTokenAddress].getHead();
        else if (_positionType == PositionType.BORROWERS_IN_P2P)
            head = borrowersInP2P[_poolTokenAddress].getHead();
        else if (_positionType == PositionType.BORROWERS_ON_POOL)
            head = borrowersOnPool[_poolTokenAddress].getHead();
    }

    /// @notice Gets the next user after `_user` in the data structure on a specific market (for UI).
    /// @param _poolTokenAddress The address of the market from which to get the user.
    /// @param _positionType The type of user from which to get the next user.
    /// @param _user The address of the user from which to get the next user.
    /// @return next The next user in the data structure.
    function getNext(
        address _poolTokenAddress,
        PositionType _positionType,
        address _user
    ) external view returns (address next) {
        if (_positionType == PositionType.SUPPLIERS_IN_P2P)
            next = suppliersInP2P[_poolTokenAddress].getNext(_user);
        else if (_positionType == PositionType.SUPPLIERS_ON_POOL)
            next = suppliersOnPool[_poolTokenAddress].getNext(_user);
        else if (_positionType == PositionType.BORROWERS_IN_P2P)
            next = borrowersInP2P[_poolTokenAddress].getNext(_user);
        else if (_positionType == PositionType.BORROWERS_ON_POOL)
            next = borrowersOnPool[_poolTokenAddress].getNext(_user);
    }

    /// @notice Returns the collateral value, debt value and max debt value of a given user.
    /// @dev Note: must be called after calling `accrueInterest()` on the cToken to have the most up to date values.
    /// @param _user The user to determine liquidity for.
    /// @return collateralValue The collateral value of the user.
    /// @return debtValue The current debt value of the user.
    /// @return maxDebtValue The maximum possible debt value of the user.
    function getUserBalanceStates(address _user)
        external
        view
        returns (
            uint256 collateralValue,
            uint256 debtValue,
            uint256 maxDebtValue
        )
    {
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
        uint256 numberOfEnteredMarkets = enteredMarkets[_user].length;
        uint256 i;

        while (i < numberOfEnteredMarkets) {
            address poolTokenEntered = enteredMarkets[_user][i];
            AssetLiquidityData memory assetData = _getUserLiquidityDataForAsset(
                _user,
                poolTokenEntered,
                oracle
            );

            unchecked {
                collateralValue += assetData.collateralValue;
                maxDebtValue += assetData.maxDebtValue;
                debtValue += assetData.debtValue;
                ++i;
            }
        }
    }

    /// @notice Returns the maximum amount available to withdraw and borrow for `_user` related to `_poolTokenAddress` (in underlyings).
    /// @dev Note: must be called after calling `accrueInterest()` on the cToken to have the most up to date values.
    /// @param _user The user to determine the capacities for.
    /// @param _poolTokenAddress The address of the market.
    /// @return withdrawable The maximum withdrawable amount of underlying token allowed (in underlying).
    /// @return borrowable The maximum borrowable amount of underlying token allowed (in underlying).
    function getUserMaxCapacitiesForAsset(address _user, address _poolTokenAddress)
        external
        view
        returns (uint256 withdrawable, uint256 borrowable)
    {
        LiquidityData memory data;
        AssetLiquidityData memory assetData;
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());
        uint256 numberOfEnteredMarkets = enteredMarkets[_user].length;
        uint256 i;

        while (i < numberOfEnteredMarkets) {
            address poolTokenEntered = enteredMarkets[_user][i];

            if (_poolTokenAddress != poolTokenEntered) {
                assetData = _getUserLiquidityDataForAsset(_user, poolTokenEntered, oracle);

                unchecked {
                    data.maxDebtValue += assetData.maxDebtValue;
                    data.debtValue += assetData.debtValue;
                }
            }

            unchecked {
                ++i;
            }
        }

        assetData = _getUserLiquidityDataForAsset(_user, _poolTokenAddress, oracle);

        unchecked {
            data.maxDebtValue += assetData.maxDebtValue;
            data.debtValue += assetData.debtValue;
        }

        // Not possible to withdraw nor borrow.
        if (data.maxDebtValue < data.debtValue) return (0, 0);

        uint256 differenceInUnderlying = (data.maxDebtValue - data.debtValue).div(
            assetData.underlyingPrice
        );

        withdrawable = assetData.collateralValue.div(assetData.underlyingPrice);
        if (assetData.collateralFactor != 0) {
            withdrawable = Math.min(
                withdrawable,
                differenceInUnderlying.div(assetData.collateralFactor)
            );
        }

        borrowable = differenceInUnderlying;
    }

    /// @notice Returns the data related to `_poolTokenAddress` for the `_user`.
    /// @dev Note: must be called after calling `accrueInterest()` on the cToken to have the most up to date values.
    /// @param _user The user to determine data for.
    /// @param _poolTokenAddress The address of the market.
    /// @param _poolTokenAddress The address of the market.
    /// @param _oracle The oracle used.
    /// @return assetData The data related to this asset.
    function getUserLiquidityDataForAsset(
        address _user,
        address _poolTokenAddress,
        ICompoundOracle _oracle
    ) external view returns (AssetLiquidityData memory assetData) {
        return _getUserLiquidityDataForAsset(_user, _poolTokenAddress, _oracle);
    }

    // Allows to receive ETH.
    receive() external payable {}
}
