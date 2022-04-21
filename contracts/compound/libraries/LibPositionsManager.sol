// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../interfaces/compound/ICompound.sol";
import "../interfaces/IWETH.sol";

import {LibStorage, MarketsStorage, PositionsStorage} from "./LibStorage.sol";
import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "../../common/libraries/DoubleLinkedList.sol";
import "./LibPositionsManagerGetters.sol";
import "./LibMatchingEngine.sol";
import "./CompoundMath.sol";
import "./Types.sol";

library LibPositionsManager {
    using DoubleLinkedList for DoubleLinkedList.List;
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;

    /// STRUCTS ///

    // Struct to avoid stack too deep.
    struct SupplyVars {
        uint256 remainingToSupply;
        uint256 borrowPoolIndex;
        uint256 toRepay;
    }

    // Struct to avoid stack too deep.
    struct BorrowVars {
        uint256 remainingToBorrow;
        uint256 poolSupplyIndex;
        uint256 balanceBefore;
        uint256 withdrawable;
        uint256 balanceAfter;
        uint256 toWithdraw;
    }

    // Struct to avoid stack too deep.
    struct WithdrawVars {
        uint256 supplyP2PExchangeRate;
        uint256 remainingToWithdraw;
        uint256 supplyPoolIndex;
        uint256 withdrawable;
        uint256 toWithdraw;
        uint256 diff;
    }

    // Struct to avoid stack too deep.
    struct RepayVars {
        uint256 supplyP2PExchangeRate;
        uint256 borrowP2PExchangeRate;
        uint256 remainingToRepay;
        uint256 borrowPoolIndex;
        uint256 feeToRepay;
        uint256 toRepay;
        uint256 diffP2P;
        uint256 inP2P;
    }

    /// STORAGE ///

    uint8 public constant CTOKEN_DECIMALS = 8;

    /// EVENTS ///

    /// @notice Emitted when the borrow P2P delta is updated.
    /// @param _poolTokenAddress The address of the market.
    /// @param _borrowP2PDelta The borrow P2P delta after update.
    event BorrowP2PDeltaUpdated(address indexed _poolTokenAddress, uint256 _borrowP2PDelta);

    /// @notice Emitted when the supply P2P delta is updated.
    /// @param _poolTokenAddress The address of the market.
    /// @param _supplyP2PDelta The supply P2P delta after update.
    event SupplyP2PDeltaUpdated(address indexed _poolTokenAddress, uint256 _supplyP2PDelta);

    /// @notice Emitted when the supply and borrow P2P amounts are updated.
    /// @param _poolTokenAddress The address of the market.
    /// @param _supplyP2PAmount The supply P2P amount after update.
    /// @param _borrowP2PAmount The borrow P2P amount after update.
    event P2PAmountsUpdated(
        address indexed _poolTokenAddress,
        uint256 _supplyP2PAmount,
        uint256 _borrowP2PAmount
    );

    /// ERRORS ///

    /// @notice Thrown when the borrow on Compound failed.
    error BorrowOnCompoundFailed();

    /// @notice Thrown when the redeem on Compound failed .
    error RedeemOnCompoundFailed();

    /// @notice Thrown when the repay on Compound failed.
    error RepayOnCompoundFailed();

    /// @notice Thrown when the mint on Compound failed.
    error MintOnCompoundFailed();

    /// @notice Thrown when the debt value is above the maximum debt value.
    error DebtValueAboveMax();

    /// @notice Thrown when the market is not created yet.
    error MarketNotCreated();

    /// @notice Thrown when the market is paused.
    error MarketPaused();

    /// MODIFIERS ///

    /// @notice Prevents a user to trigger a function when market is not created or paused.
    /// @param _poolTokenAddress The address of the market to check.
    modifier isMarketCreatedAndNotPaused(address _poolTokenAddress) {
        MarketsStorage storage m = ms();
        if (!m.isCreated[_poolTokenAddress]) revert MarketNotCreated();
        if (m.paused[_poolTokenAddress]) revert MarketPaused();
        _;
    }

    /// STORAGE GETTERS ///

    function ms() internal pure returns (MarketsStorage storage) {
        return LibStorage.marketsStorage();
    }

    function ps() internal pure returns (PositionsStorage storage) {
        return LibStorage.positionsStorage();
    }

    /// LOGIC ///

    /// @dev Implements supply logic.
    /// @param _poolTokenAddress The address of the pool token the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) public isMarketCreatedAndNotPaused(_poolTokenAddress) {
        _enterMarketIfNeeded(_poolTokenAddress, msg.sender);
        MarketsStorage storage m = ms();
        PositionsStorage storage p = ps();

        ERC20 underlyingToken = LibPositionsManagerGetters.getUnderlying(_poolTokenAddress);
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);

        Types.Delta storage delta = p.deltas[_poolTokenAddress];
        SupplyVars memory vars;
        vars.borrowPoolIndex = ICToken(_poolTokenAddress).borrowIndex();
        vars.remainingToSupply = _amount;
        vars.toRepay;

        /// Supply in P2P ///

        if (!m.noP2P[_poolTokenAddress]) {
            // Match borrow P2P delta first if any.
            uint256 matchedDelta;
            if (delta.borrowP2PDelta > 0) {
                matchedDelta = CompoundMath.min(
                    delta.borrowP2PDelta.mul(vars.borrowPoolIndex),
                    vars.remainingToSupply
                );
                if (matchedDelta > 0) {
                    vars.toRepay += matchedDelta;
                    vars.remainingToSupply -= matchedDelta;
                    delta.borrowP2PDelta -= matchedDelta.div(vars.borrowPoolIndex);
                    emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
                }
            }

            // Match pool suppliers if any.
            if (
                vars.remainingToSupply > 0 &&
                p.borrowersOnPool[_poolTokenAddress].getHead() != address(0)
            ) {
                uint256 matched = LibMatchingEngine.matchBorrowers(
                    ICToken(_poolTokenAddress),
                    vars.remainingToSupply,
                    _maxGasToConsume
                ); // In underlying.

                if (matched > 0) {
                    vars.toRepay += matched;
                    vars.remainingToSupply -= matched;
                    delta.borrowP2PAmount += matched.div(
                        m.borrowP2PExchangeRate[_poolTokenAddress]
                    );
                }
            }
        }

        if (vars.toRepay > 0) {
            uint256 toAddInP2P = vars.toRepay.div(m.supplyP2PExchangeRate[_poolTokenAddress]);

            delta.supplyP2PAmount += toAddInP2P;
            p.supplyBalanceInOf[_poolTokenAddress][msg.sender].inP2P += toAddInP2P;
            LibMatchingEngine.updateSuppliers(_poolTokenAddress, msg.sender);

            // Repay only what is necessary. The remaining tokens stays on the contracts and are claimable by the DAO.
            vars.toRepay = Math.min(
                vars.toRepay,
                ICToken(_poolTokenAddress).borrowBalanceCurrent(address(this)) // The debt of the contract.
            );

            _repayToPool(_poolTokenAddress, underlyingToken, vars.toRepay); // Reverts on error.
            emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);
        }

        /// Supply on pool ///

        if (vars.remainingToSupply > 0) {
            p.supplyBalanceInOf[_poolTokenAddress][msg.sender].onPool += vars.remainingToSupply.div(
                ICToken(_poolTokenAddress).exchangeRateCurrent()
            ); // In scaled balance.
            LibMatchingEngine.updateSuppliers(_poolTokenAddress, msg.sender);
            _supplyToPool(_poolTokenAddress, underlyingToken, vars.remainingToSupply); // Reverts on error.
        }
    }

    /// @dev Implements borrow logic.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) public isMarketCreatedAndNotPaused(_poolTokenAddress) {
        _enterMarketIfNeeded(_poolTokenAddress, msg.sender);
        checkUserLiquidity(msg.sender, _poolTokenAddress, 0, _amount);
        PositionsStorage storage p = ps();
        Types.Delta storage delta = p.deltas[_poolTokenAddress];
        BorrowVars memory vars;
        ERC20 underlyingToken = LibPositionsManagerGetters.getUnderlying(_poolTokenAddress);
        vars.balanceBefore = underlyingToken.balanceOf(address(this));
        vars.remainingToBorrow = _amount;
        vars.poolSupplyIndex = ICToken(_poolTokenAddress).exchangeRateCurrent();
        vars.withdrawable = ICToken(_poolTokenAddress).balanceOfUnderlying(address(this)); // The balance on pool.

        /// Borrow in P2P ///

        if (!ms().noP2P[_poolTokenAddress]) {
            // Match supply P2P delta first if any.
            uint256 matchedDelta;
            if (delta.supplyP2PDelta > 0) {
                matchedDelta = CompoundMath.min(
                    delta.supplyP2PDelta.mul(vars.poolSupplyIndex),
                    vars.remainingToBorrow,
                    vars.withdrawable
                );
                if (matchedDelta > 0) {
                    vars.toWithdraw += matchedDelta;
                    vars.remainingToBorrow -= matchedDelta;
                    delta.supplyP2PDelta -= matchedDelta.div(vars.poolSupplyIndex);
                    emit SupplyP2PDeltaUpdated(_poolTokenAddress, delta.supplyP2PDelta);
                }
            }

            // Match pool suppliers if any.
            if (
                vars.remainingToBorrow > 0 &&
                p.suppliersOnPool[_poolTokenAddress].getHead() != address(0)
            ) {
                uint256 matched = LibMatchingEngine.matchSuppliers(
                    ICToken(_poolTokenAddress),
                    CompoundMath.min(vars.remainingToBorrow, vars.withdrawable - vars.toWithdraw),
                    _maxGasToConsume
                ); // In underlying.

                if (matched > 0) {
                    vars.toWithdraw += matched;
                    vars.remainingToBorrow -= matched;
                    p.deltas[_poolTokenAddress].supplyP2PAmount += matched.div(
                        ms().supplyP2PExchangeRate[_poolTokenAddress]
                    );
                }
            }
        }

        if (vars.toWithdraw > 0) {
            uint256 toAddInP2P = vars.toWithdraw.div(ms().borrowP2PExchangeRate[_poolTokenAddress]); // In p2pUnit.

            p.deltas[_poolTokenAddress].borrowP2PAmount += toAddInP2P;
            p.borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P += toAddInP2P;
            LibMatchingEngine.updateBorrowers(_poolTokenAddress, msg.sender);

            _withdrawFromPool(_poolTokenAddress, vars.toWithdraw); // Reverts on error.
            emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);
        }

        /// Borrow on pool ///

        if (_isAboveCompoundThreshold(_poolTokenAddress, vars.remainingToBorrow)) {
            p.borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool += vars.remainingToBorrow.div(
                ICToken(_poolTokenAddress).borrowIndex()
            ); // In cdUnit.
            LibMatchingEngine.updateBorrowers(_poolTokenAddress, msg.sender);
            _borrowFromPool(_poolTokenAddress, vars.remainingToBorrow);
        }

        // Due to rounding errors the balance may be lower than expected.
        vars.balanceAfter = underlyingToken.balanceOf(address(this));

        underlyingToken.safeTransfer(msg.sender, vars.balanceAfter - vars.balanceBefore);
    }

    /// @dev Implements withdraw logic.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _supplier The address of the supplier.
    /// @param _receiver The address of the user who will receive the tokens.
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function withdraw(
        address _poolTokenAddress,
        uint256 _amount,
        address _supplier,
        address _receiver,
        uint256 _maxGasToConsume
    ) public isMarketCreatedAndNotPaused(_poolTokenAddress) {
        ERC20 underlyingToken = LibPositionsManagerGetters.getUnderlying(_poolTokenAddress);
        PositionsStorage storage p = ps();
        MarketsStorage storage m = ms();
        WithdrawVars memory vars;
        vars.remainingToWithdraw = _amount;
        vars.withdrawable = ICToken(_poolTokenAddress).balanceOfUnderlying(address(this));
        vars.supplyPoolIndex = ICToken(_poolTokenAddress).exchangeRateCurrent();

        /// Soft withdraw ///

        if (p.supplyBalanceInOf[_poolTokenAddress][_supplier].onPool > 0) {
            uint256 onPoolSupply = p.supplyBalanceInOf[_poolTokenAddress][_supplier].onPool;
            vars.toWithdraw = CompoundMath.min(
                onPoolSupply.mul(vars.supplyPoolIndex),
                vars.remainingToWithdraw,
                vars.withdrawable
            );
            vars.remainingToWithdraw -= vars.toWithdraw;

            // Handle case where only 1 wei stays on the position.
            vars.diff =
                p.supplyBalanceInOf[_poolTokenAddress][_supplier].onPool -
                CompoundMath.min(onPoolSupply, vars.toWithdraw.div(vars.supplyPoolIndex));
            p.supplyBalanceInOf[_poolTokenAddress][_supplier].onPool = vars.diff == 1
                ? 0
                : vars.diff;
            LibMatchingEngine.updateSuppliers(_poolTokenAddress, _supplier);

            if (vars.remainingToWithdraw == 0) {
                if (vars.toWithdraw > 0) _withdrawFromPool(_poolTokenAddress, vars.toWithdraw); // Reverts on error.
                underlyingToken.safeTransfer(_receiver, _amount);
                _leaveMarkerIfNeeded(_poolTokenAddress, _supplier);
                return;
            }
        }

        Types.Delta storage delta = p.deltas[_poolTokenAddress];
        vars.supplyP2PExchangeRate = m.supplyP2PExchangeRate[_poolTokenAddress];

        /// Transfer withdraw ///

        if (vars.remainingToWithdraw > 0 && !m.noP2P[_poolTokenAddress]) {
            p.supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P -= CompoundMath.min(
                p.supplyBalanceInOf[_poolTokenAddress][_supplier].inP2P,
                vars.remainingToWithdraw.div(vars.supplyP2PExchangeRate)
            ); // In p2pUnit
            LibMatchingEngine.updateSuppliers(_poolTokenAddress, _supplier);

            // Match Delta if any.
            if (delta.supplyP2PDelta > 0) {
                uint256 matchedDelta;
                matchedDelta = CompoundMath.min(
                    delta.supplyP2PDelta.mul(vars.supplyPoolIndex),
                    vars.remainingToWithdraw,
                    vars.withdrawable - vars.toWithdraw
                );

                if (matchedDelta > 0) {
                    vars.toWithdraw += matchedDelta;
                    vars.remainingToWithdraw -= matchedDelta;
                    delta.supplyP2PDelta -= matchedDelta.div(vars.supplyPoolIndex);
                    delta.supplyP2PAmount -= matchedDelta.div(vars.supplyP2PExchangeRate);
                    emit SupplyP2PDeltaUpdated(_poolTokenAddress, delta.supplyP2PDelta);
                }
            }

            // Match pool suppliers if any.
            if (
                vars.remainingToWithdraw > 0 &&
                p.suppliersOnPool[_poolTokenAddress].getHead() != address(0)
            ) {
                // Match suppliers.
                uint256 matched = LibMatchingEngine.matchSuppliers(
                    ICToken(_poolTokenAddress),
                    CompoundMath.min(vars.remainingToWithdraw, vars.withdrawable - vars.toWithdraw),
                    _maxGasToConsume / 2
                );

                if (matched > 0) {
                    vars.remainingToWithdraw -= matched;
                    vars.toWithdraw += matched;
                }
            }
        }

        if (vars.toWithdraw > 0) _withdrawFromPool(_poolTokenAddress, vars.toWithdraw); // Reverts on error.

        /// Hard withdraw ///

        if (vars.remainingToWithdraw > 0) {
            uint256 unmatched = LibMatchingEngine.unmatchBorrowers(
                _poolTokenAddress,
                vars.remainingToWithdraw,
                _maxGasToConsume / 2
            );

            // If unmatched does not cover remainingToWithdraw, the difference is added to the borrow P2P delta.
            if (unmatched < vars.remainingToWithdraw) {
                delta.borrowP2PDelta += (vars.remainingToWithdraw - unmatched).div(
                    ICToken(_poolTokenAddress).borrowIndex()
                );
                emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PAmount);
            }

            delta.supplyP2PAmount -= vars.remainingToWithdraw.div(vars.supplyP2PExchangeRate);
            delta.borrowP2PAmount -= unmatched.div(m.borrowP2PExchangeRate[_poolTokenAddress]);
            emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);

            _borrowFromPool(_poolTokenAddress, vars.remainingToWithdraw); // Reverts on error.
        }

        underlyingToken.safeTransfer(_receiver, _amount);
        _leaveMarkerIfNeeded(_poolTokenAddress, _supplier);
    }

    /// @dev Implements repay logic.
    /// @dev Note: `msg.sender` must have approved this contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _user The address of the user.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function repay(
        address _poolTokenAddress,
        address _user,
        uint256 _amount,
        uint256 _maxGasToConsume
    ) public isMarketCreatedAndNotPaused(_poolTokenAddress) {
        ICToken poolToken = ICToken(_poolTokenAddress);
        ERC20 underlyingToken = LibPositionsManagerGetters.getUnderlying(_poolTokenAddress);
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
        PositionsStorage storage p = ps();
        RepayVars memory vars;
        vars.remainingToRepay = _amount;
        vars.borrowPoolIndex = poolToken.borrowIndex();

        /// Soft repay ///

        if (p.borrowBalanceInOf[_poolTokenAddress][_user].onPool > 0) {
            uint256 borrowedOnPool = p.borrowBalanceInOf[_poolTokenAddress][_user].onPool;
            vars.toRepay = CompoundMath.min(
                borrowedOnPool.mul(vars.borrowPoolIndex),
                vars.remainingToRepay
            );
            vars.remainingToRepay -= vars.toRepay;

            // Handle case where only 1 wei stays on the position.
            uint256 diffPool = p.borrowBalanceInOf[_poolTokenAddress][_user].onPool -
                CompoundMath.min(borrowedOnPool, vars.toRepay.div(vars.borrowPoolIndex));
            p.borrowBalanceInOf[_poolTokenAddress][_user].onPool = diffPool == 1 ? 0 : diffPool; // In cdUnit.
            LibMatchingEngine.updateBorrowers(_poolTokenAddress, _user);

            if (vars.remainingToRepay == 0) {
                // Repay only what is necessary. The remaining tokens stays on the contracts and are claimable by the DAO.
                vars.toRepay = Math.min(
                    vars.toRepay,
                    ICToken(_poolTokenAddress).borrowBalanceCurrent(address(this)) // The debt of the contract.
                );

                if (vars.toRepay > 0)
                    _repayToPool(_poolTokenAddress, underlyingToken, vars.toRepay); // Reverts on error.
                _leaveMarkerIfNeeded(_poolTokenAddress, _user);
                return;
            }
        }

        Types.Delta storage delta = p.deltas[_poolTokenAddress];
        MarketsStorage storage m = ms();
        vars.supplyP2PExchangeRate = m.supplyP2PExchangeRate[_poolTokenAddress];
        vars.borrowP2PExchangeRate = m.borrowP2PExchangeRate[_poolTokenAddress];
        // Handle case where only 1 wei stays on the position.
        vars.inP2P = p.borrowBalanceInOf[_poolTokenAddress][_user].inP2P;
        vars.diffP2P =
            vars.inP2P -
            CompoundMath.min(vars.inP2P, vars.remainingToRepay.div(vars.borrowP2PExchangeRate));
        p.borrowBalanceInOf[_poolTokenAddress][_user].inP2P = vars.diffP2P == 1 ? 0 : vars.diffP2P; // In p2pUnit.
        LibMatchingEngine.updateBorrowers(_poolTokenAddress, _user);

        /// Fee repay ///

        // Fee = (supplyP2P - supplyP2PDelta) - (borrowP2P - borrowP2PDelta)
        vars.feeToRepay = CompoundMath.safeSub(
            (delta.borrowP2PAmount.mul(vars.borrowP2PExchangeRate) -
                delta.borrowP2PDelta.mul(vars.borrowPoolIndex)),
            (delta.supplyP2PAmount.mul(vars.supplyP2PExchangeRate) -
                delta.supplyP2PDelta.mul(poolToken.exchangeRateStored()))
        );
        vars.remainingToRepay -= vars.feeToRepay;

        /// Transfer repay ///

        if (vars.remainingToRepay > 0 && !m.noP2P[_poolTokenAddress]) {
            // Match Delta if any.
            if (delta.borrowP2PDelta > 0) {
                uint256 matchedDelta = CompoundMath.min(
                    delta.borrowP2PDelta.mul(vars.borrowPoolIndex),
                    vars.remainingToRepay
                );

                if (matchedDelta > 0) {
                    vars.toRepay += matchedDelta;
                    vars.remainingToRepay -= matchedDelta;
                    delta.borrowP2PDelta -= matchedDelta.div(vars.borrowPoolIndex);
                    delta.borrowP2PAmount -= matchedDelta.div(vars.borrowP2PExchangeRate);
                    emit BorrowP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
                }
            }

            if (
                vars.remainingToRepay > 0 &&
                p.borrowersOnPool[_poolTokenAddress].getHead() != address(0)
            ) {
                // Match borrowers.
                uint256 matched = LibMatchingEngine.matchBorrowers(
                    poolToken,
                    vars.remainingToRepay,
                    _maxGasToConsume / 2
                );

                if (matched > 0) {
                    vars.remainingToRepay -= matched;
                    vars.toRepay += matched;
                }
            }
        }

        // Repay only what is necessary. The remaining tokens stays on the contracts and are claimable by the DAO.
        vars.toRepay = Math.min(
            vars.toRepay,
            ICToken(_poolTokenAddress).borrowBalanceCurrent(address(this)) // The debt of the contract.
        );

        if (vars.toRepay > 0) _repayToPool(_poolTokenAddress, underlyingToken, vars.toRepay); // Reverts on error.

        /// Hard repay ///

        if (vars.remainingToRepay > 0) {
            uint256 unmatched = LibMatchingEngine.unmatchSuppliers(
                _poolTokenAddress,
                vars.remainingToRepay,
                _maxGasToConsume / 2
            ); // Reverts on error.

            // If unmatched does not cover remainingToRepay, the difference is added to the supply P2P delta.
            if (unmatched < vars.remainingToRepay) {
                delta.supplyP2PDelta += (vars.remainingToRepay - unmatched).div(
                    poolToken.exchangeRateStored() // We must re-call the pool because the exchange rate may have changed after repay.
                );
                emit SupplyP2PDeltaUpdated(_poolTokenAddress, delta.borrowP2PDelta);
            }

            delta.supplyP2PAmount -= unmatched.div(vars.supplyP2PExchangeRate);
            delta.borrowP2PAmount -= vars.remainingToRepay.div(vars.borrowP2PExchangeRate);
            emit P2PAmountsUpdated(_poolTokenAddress, delta.supplyP2PAmount, delta.borrowP2PAmount);

            _supplyToPool(_poolTokenAddress, underlyingToken, vars.remainingToRepay); // Reverts on error.
        }

        _leaveMarkerIfNeeded(_poolTokenAddress, _user);
    }

    /// @dev Checks whether the user can borrow/withdraw or not.
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically withdraw/borrow in.
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    function checkUserLiquidity(
        address _user,
        address _poolTokenAddress,
        uint256 _withdrawnAmount,
        uint256 _borrowedAmount
    ) public {
        (uint256 debtValue, uint256 maxDebtValue) = LibPositionsManagerGetters
        .getUserHypotheticalBalanceStates(
            _user,
            _poolTokenAddress,
            _withdrawnAmount,
            _borrowedAmount
        );
        if (debtValue > maxDebtValue) revert DebtValueAboveMax();
    }

    /// @dev Enters the user into the market if not already there.
    /// @param _user The address of the user to update.
    /// @param _poolTokenAddress The address of the market to check.
    function _enterMarketIfNeeded(address _poolTokenAddress, address _user) public {
        PositionsStorage storage p = ps();
        if (!p.userMembership[_poolTokenAddress][_user]) {
            p.userMembership[_poolTokenAddress][_user] = true;
            p.enteredMarkets[_user].push(_poolTokenAddress);
        }
    }

    /// @dev Removes the user from the market if he has no funds or borrow on it.
    /// @param _user The address of the user to update.
    /// @param _poolTokenAddress The address of the market to check.
    function _leaveMarkerIfNeeded(address _poolTokenAddress, address _user) public {
        PositionsStorage storage p = ps();
        if (
            p.supplyBalanceInOf[_poolTokenAddress][_user].inP2P == 0 &&
            p.supplyBalanceInOf[_poolTokenAddress][_user].onPool == 0 &&
            p.borrowBalanceInOf[_poolTokenAddress][_user].inP2P == 0 &&
            p.borrowBalanceInOf[_poolTokenAddress][_user].onPool == 0
        ) {
            uint256 index;
            while (p.enteredMarkets[_user][index] != _poolTokenAddress) {
                unchecked {
                    ++index;
                }
            }
            p.userMembership[_poolTokenAddress][_user] = false;

            uint256 length = p.enteredMarkets[_user].length;
            if (index != length - 1)
                p.enteredMarkets[_user][index] = p.enteredMarkets[_user][length - 1];
            p.enteredMarkets[_user].pop();
        }
    }

    /// @dev Supplies underlying tokens to Compound.
    /// @param _poolTokenAddress The address of the pool token.
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _amount The amount of token (in underlying).
    function _supplyToPool(
        address _poolTokenAddress,
        ERC20 _underlyingToken,
        uint256 _amount
    ) public {
        PositionsStorage storage p = ps();
        if (_poolTokenAddress == p.cEth) {
            IWETH(p.wEth).withdraw(_amount); // Turn wETH into ETH.
            ICEther(_poolTokenAddress).mint{value: _amount}();
        } else {
            _underlyingToken.safeApprove(_poolTokenAddress, _amount);
            if (ICToken(_poolTokenAddress).mint(_amount) != 0) revert MintOnCompoundFailed();
        }
    }

    /// @dev Withdraws underlying tokens from Compound.
    /// @param _poolTokenAddress The address of the pool token.
    /// @param _amount The amount of token (in underlying).
    function _withdrawFromPool(address _poolTokenAddress, uint256 _amount) public {
        if (ICToken(_poolTokenAddress).redeemUnderlying(_amount) != 0)
            revert RedeemOnCompoundFailed();
        PositionsStorage storage p = ps();
        if (_poolTokenAddress == p.cEth) IWETH(p.wEth).deposit{value: _amount}(); // Turn the ETH recceived in wETH.
    }

    /// @dev Borrows underlying tokens from Compound.
    /// @param _poolTokenAddress The address of the pool token.
    /// @param _amount The amount of token (in underlying).
    function _borrowFromPool(address _poolTokenAddress, uint256 _amount) public {
        if ((ICToken(_poolTokenAddress).borrow(_amount) != 0)) revert BorrowOnCompoundFailed();
        PositionsStorage storage p = ps();
        if (_poolTokenAddress == p.cEth) IWETH(p.wEth).deposit{value: _amount}(); // Turn the ETH recceived in wETH.
    }

    /// @dev Repays underlying tokens to Compound.
    /// @param _poolTokenAddress The address of the pool token.
    /// @param _underlyingToken The underlying token of the market to repay to.
    /// @param _amount The amount of token (in underlying).
    function _repayToPool(
        address _poolTokenAddress,
        ERC20 _underlyingToken,
        uint256 _amount
    ) public {
        PositionsStorage storage p = ps();
        if (_poolTokenAddress == p.cEth) {
            IWETH(p.wEth).withdraw(_amount); // Turn wETH into ETH.
            ICEther(_poolTokenAddress).repayBorrow{value: _amount}();
        } else {
            _underlyingToken.safeApprove(_poolTokenAddress, _amount);
            if (ICToken(_poolTokenAddress).repayBorrow(_amount) != 0)
                revert RepayOnCompoundFailed();
        }
    }

    /// @dev Returns whether it is unsafe supply/witdhraw due to coumpound's revert on low levels of precision or not.
    /// @param _amount The amount of token considered for depositing/redeeming.
    /// @param _poolTokenAddress poolToken address of the considered market.
    /// @return Whether to continue or not.
    function _isAboveCompoundThreshold(address _poolTokenAddress, uint256 _amount)
        public
        view
        returns (bool)
    {
        uint8 tokenDecimals = LibPositionsManagerGetters
        .getUnderlying(_poolTokenAddress)
        .decimals();
        if (tokenDecimals > CTOKEN_DECIMALS) {
            // Multiply by 2 to have a safety buffer.
            unchecked {
                return (_amount > 2 * 10**(tokenDecimals - CTOKEN_DECIMALS));
            }
        } else return true;
    }
}
