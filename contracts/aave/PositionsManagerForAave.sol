// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./MatchingEngineForAave.sol";

import "./PositionsManagerParts/PositionsManagerForAaveCore.sol";

/// @title PositionsManagerForAave
/// @notice Smart contract interacting with Aave to enable P2P supply/borrow positions that can fallback on Aave's pool using pool tokens.
///     This file is for the main user-facing functions
contract PositionsManagerForAave is PositionsManagerForAaveCore {
    using MatchingEngineFns for IMatchingEngineForAave;
    using SafeERC20 for IERC20;

    /// Constructor ///

    /// @notice Constructs the PositionsManagerForAave contract.
    /// @param _marketsManager The address of the aave `marketsManager`.
    /// @param _lendingPoolAddressesProvider The address of the `addressesProvider`.
    /// @param _swapManager The `swapManager`.
    constructor(
        address _marketsManager,
        address _lendingPoolAddressesProvider,
        ISwapManager _swapManager,
        MaxGas memory _maxGas
    ) {
        maxGas = _maxGas;
        marketsManager = IMarketsManagerForAave(_marketsManager);
        addressesProvider = ILendingPoolAddressesProvider(_lendingPoolAddressesProvider);
        dataProvider = IProtocolDataProvider(addressesProvider.getAddress(DATA_PROVIDER_ID));
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
        matchingEngine = new MatchingEngineForAave();
        swapManager = _swapManager;
    }

    /// @notice Transfers the protocol reserve fee to the DAO.
    /// @param _poolTokenAddress The address of the market on which we want to claim the reserve fee.
    function claimToTreasury(address _poolTokenAddress)
        external
        whenNotPaused
        onlyMarketsManagerOwner
        isMarketCreated(_poolTokenAddress)
    {
        IERC20 underlyingToken = IERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        uint256 amountToClaim = underlyingToken.balanceOf(address(this));
        underlyingToken.safeTransfer(treasuryVault, amountToClaim);
        emit ReserveFeeClaimed(_poolTokenAddress, amountToClaim);
    }

    /// @notice Claims rewards for the given assets and the unclaimed rewards.
    /// @param _assets The assets to claim rewards from (aToken or variable debt token).
    /// @param _swap Whether or not to swap reward tokens for Morpho tokens.
    function claimRewards(address[] calldata _assets, bool _swap) external whenNotPaused {
        uint256 amountToClaim = rewardsManager.claimRewards(_assets, type(uint256).max, msg.sender);

        if (amountToClaim > 0) {
            if (_swap) {
                uint256 amountClaimed = aaveIncentivesController.claimRewards(
                    _assets,
                    amountToClaim,
                    address(swapManager)
                );
                uint256 amountOut = swapManager.swapToMorphoToken(amountClaimed, msg.sender);
                emit RewardsClaimedAndSwapped(msg.sender, amountClaimed, amountOut);
            } else {
                uint256 amountClaimed = aaveIncentivesController.claimRewards(
                    _assets,
                    amountToClaim,
                    msg.sender
                );
                emit RewardsClaimed(msg.sender, amountClaimed);
            }
        }
    }

    /// @notice Supplies underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to supply.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode
    )
        external
        nonReentrant
        whenNotPaused
        isMarketCreated(_poolTokenAddress)
        isAboveThreshold(_poolTokenAddress, _amount)
    {
        _supply(_poolTokenAddress, _amount, _referralCode, maxGas.supply);
    }

    /// @dev Supplies underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to supply.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function supply(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode,
        uint256 _maxGasToConsume
    )
        external
        nonReentrant
        isMarketCreated(_poolTokenAddress)
        isAboveThreshold(_poolTokenAddress, _amount)
    {
        _supply(_poolTokenAddress, _amount, _referralCode, _maxGasToConsume);
    }

    /// @notice Borrows underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the markets the user wants to enter.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode
    )
        external
        nonReentrant
        whenNotPaused
        isMarketCreated(_poolTokenAddress)
        isAboveThreshold(_poolTokenAddress, _amount)
    {
        _borrow(_poolTokenAddress, _amount, _referralCode, maxGas.borrow);
    }

    /// @dev Supplies underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to supply.
    /// @param _amount The amount of token (in underlying).
    /// @param _referralCode The referral code of an integrator that may receive rewards. 0 if no referral code.
    /// @param _maxGasToConsume The maximum amount of gas to consume within a matching engine loop.
    function borrow(
        address _poolTokenAddress,
        uint256 _amount,
        uint16 _referralCode,
        uint256 _maxGasToConsume
    )
        external
        nonReentrant
        isMarketCreated(_poolTokenAddress)
        isAboveThreshold(_poolTokenAddress, _amount)
    {
        _borrow(_poolTokenAddress, _amount, _referralCode, _maxGasToConsume);
    }

    /// @notice Withdraws underlying tokens in a specific market.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount in tokens to withdraw from supply.
    function withdraw(address _poolTokenAddress, uint256 _amount)
        external
        nonReentrant
        whenNotPaused
    {
        marketsManager.updateP2PExchangeRates(_poolTokenAddress);
        IAToken poolToken = IAToken(_poolTokenAddress);

        uint256 toWithdraw = Math.min(
            _getUserSupplyBalanceInOf(
                _poolTokenAddress,
                msg.sender,
                poolToken.UNDERLYING_ASSET_ADDRESS()
            ),
            _amount
        );

        _withdraw(_poolTokenAddress, toWithdraw, msg.sender, msg.sender, maxGas.withdraw);
    }

    /// @notice Repays debt of the user.
    /// @dev `msg.sender` must have approved Morpho's contract to spend the underlying `_amount`.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    function repay(address _poolTokenAddress, uint256 _amount) external nonReentrant whenNotPaused {
        marketsManager.updateP2PExchangeRates(_poolTokenAddress);
        IAToken poolToken = IAToken(_poolTokenAddress);

        uint256 toRepay = Math.min(
            _getUserBorrowBalanceInOf(
                _poolTokenAddress,
                msg.sender,
                poolToken.UNDERLYING_ASSET_ADDRESS()
            ),
            _amount
        );

        _repay(_poolTokenAddress, msg.sender, toRepay, maxGas.repay);
    }
}
