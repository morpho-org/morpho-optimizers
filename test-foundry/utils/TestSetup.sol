// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "lib/ds-test/src/test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@contracts/aave/PositionsManagerForAave.sol";
import "@contracts/aave/MarketsManagerForAave.sol";
import "@contracts/aave/test/SimplePriceOracle.sol";
import "@config/Config.sol";
import "./HEVM.sol";
import "./Utils.sol";
import "./User.sol";

contract TestSetup is DSTest, Config, Utils {
    using WadRayMath for uint256;

    struct Asset {
        uint256 amount;
        address poolToken;
        address underlying;
    }

    HEVM hevm = HEVM(HEVM_ADDRESS);

    PositionsManagerForAave internal positionsManager;
    PositionsManagerForAave internal fakePositionsManager;
    MarketsManagerForAave internal marketsManager;

    ILendingPoolAddressesProvider lendingPoolAddressesProvider;
    ILendingPool lendingPool;
    IProtocolDataProvider protocolDataProvider;
    IPriceOracleGetter oracle;

    User supplier1;
    User supplier2;
    User supplier3;
    User[] suppliers;

    User borrower1;
    User borrower2;
    User borrower3;
    User[] borrowers;

    address[] pools;

    function setUp() public {
        marketsManager = new MarketsManagerForAave(lendingPoolAddressesProviderAddress);
        positionsManager = new PositionsManagerForAave(
            address(marketsManager),
            lendingPoolAddressesProviderAddress
        );

        fakePositionsManager = new PositionsManagerForAave(
            address(marketsManager),
            lendingPoolAddressesProviderAddress
        );

        lendingPoolAddressesProvider = ILendingPoolAddressesProvider(
            lendingPoolAddressesProviderAddress
        );
        lendingPool = ILendingPool(lendingPoolAddressesProvider.getLendingPool());

        protocolDataProvider = IProtocolDataProvider(protocolDataProviderAddress);

        oracle = IPriceOracleGetter(lendingPoolAddressesProvider.getPriceOracle());

        marketsManager.setPositionsManager(address(positionsManager));
        marketsManager.updateLendingPool();
        // !!! WARNING !!!
        // All tokens must also be added to the pools array, for the correct behavior of TestLiquidate::createAndSetCustomPriceOracle.
        marketsManager.createMarket(aDai, WAD, type(uint256).max);
        pools.push(aDai);
        marketsManager.createMarket(aUsdc, to6Decimals(WAD), type(uint256).max);
        pools.push(aUsdc);
        marketsManager.createMarket(aWbtc, 10**4, type(uint256).max);
        pools.push(aWbtc);
        marketsManager.createMarket(aUsdt, to6Decimals(WAD), type(uint256).max);
        pools.push(aUsdt);
        marketsManager.createMarket(aWmatic, WAD, type(uint256).max);
        pools.push(aWmatic);

        for (uint256 i = 0; i < 3; i++) {
            suppliers.push(new User(positionsManager, marketsManager));
            fillBalances(address(suppliers[i]));
        }
        supplier1 = suppliers[0];
        supplier2 = suppliers[1];
        supplier3 = suppliers[2];

        for (uint256 i = 0; i < 3; i++) {
            borrowers.push(new User(positionsManager, marketsManager));
            fillBalances(address(borrowers[i]));
        }
        borrower1 = borrowers[0];
        borrower2 = borrowers[1];
        borrower3 = borrowers[2];
    }

    /**
     * @dev Fill all user's balances of tokens in pools with uint128 max value.
     * @param _user  user address
     */
    function fillBalances(address _user) internal {
        for (uint256 i = 0; i < pools.length; i++) {
            writeBalanceOf(_user, IAToken(pools[i]).UNDERLYING_ASSET_ADDRESS(), type(uint128).max);
        }
    }

    /**
     * @dev Write the balance of `_who` for `_acct` token with `_value`amount.
     * @param _who  user address
     * @param _acct  token address
     * @param _value  amount
     */
    function writeBalanceOf(
        address _who,
        address _acct,
        uint256 _value
    ) internal {
        hevm.store(_acct, keccak256(abi.encode(_who, slots[_acct])), bytes32(_value));
    }

    /**
     * @dev Set NMAX, create the same number of suppliers and borrowers,
     *      and fill their balances.
     * @param _NMAX new NMAX
     */
    function setNMAXAndCreateSigners(uint16 _NMAX) internal {
        marketsManager.setNmaxForMatchingEngine(_NMAX);

        while (borrowers.length < _NMAX) {
            borrowers.push(new User(positionsManager, marketsManager));
            fillBalances(address(borrowers[borrowers.length - 1]));

            suppliers.push(new User(positionsManager, marketsManager));
            fillBalances(address(suppliers[suppliers.length - 1]));
        }
    }

    function testEquality(uint256 _firstValue, uint256 _secondValue) internal {
        assertLe(getAbsDiff(_firstValue, _secondValue), 15);
    }

    /**
     * @dev Returns an amount which is greater than the supplied asset threshold.
     * @notice It caps the amount to 15 billions
     * @param _amount    amount of asset
     * @param _supplyAsset   aToken address
     */
    function getSupplyAmount(uint256 _amount, address _supplyAsset) internal returns (uint256) {
        address underlying = IAToken(_supplyAsset).UNDERLYING_ASSET_ADDRESS();
        _amount = denormalizeAmount(_amount, underlying);

        // Cap amount to 15 B
        uint256 amountInUsdc = underlying == usdc
            ? _amount
            : getValueOfIn(_amount, underlying, usdc);
        uint256 value15b = 15 * 10**(6 + 9);
        if (amountInUsdc > value15b) {
            emit log_string("amountInUsdc > value15b");
            _amount = underlying == usdc ? value15b : getValueOfIn(value15b, usdc, underlying);
            emit log_named_decimal_uint("new amount", _amount, ERC20(usdc).decimals());
        }

        // Check that amount is greater than threshold
        uint256 threshold = positionsManager.threshold(_supplyAsset);
        if (_amount < threshold) {
            emit log_string("_amount < threshold");
            _amount += threshold;
            emit log_named_decimal_uint("new amount", _amount, ERC20(usdc).decimals());
        }

        return _amount;
    }

    function denormalizeAmount(uint256 _amount, address _erc20) internal view returns (uint256) {
        uint256 decimals = ERC20(_erc20).decimals();

        return decimals == 18 ? _amount : _amount / 10**(18 - decimals);
    }

    function normalizeAmount(uint256 _amount, address _erc20) internal view returns (uint256) {
        uint256 decimals = ERC20(_erc20).decimals();

        return decimals == 18 ? _amount : _amount * 10**(18 - decimals);
    }

    /**
     * @dev Returns the amount, pool token address and underlying address for a supplied asset.
     * @notice An event with the token symbol is emmitted for easier debug.
     * @param _amount    amount to check
     * @param _index     index of pool token
     * @param _useUsdt   use USDT as supply token
     */
    function getSupplyAsset(
        uint256 _amount,
        uint8 _index,
        bool _useUsdt
    ) internal returns (Asset memory) {
        uint256 index = _index % pools.length;

        if (!_useUsdt && pools[index] == aUsdt) {
            index--;
        }

        address underlying = IAToken(pools[index]).UNDERLYING_ASSET_ADDRESS();
        emit log_named_string("supply", ERC20(underlying).symbol());

        Asset memory asset = Asset(
            getSupplyAmount(_amount, pools[index]),
            pools[index],
            underlying
        );

        return asset;
    }

    /**
     * @dev Returns the pool token address and underlying address of a borrowed asset.
     * @notice The pool token will be different from the supply pool token.
     * @notice An event with the token symbol is emmitted for easier debug.
     * @param _borrowIndex   index of token
     * @param _supplyPoolToken   pool token for supply
     */
    function getBorrowAsset(uint8 _borrowIndex, address _supplyPoolToken)
        internal
        returns (Asset memory)
    {
        uint256 borrowIndex = _borrowIndex % pools.length;

        // Check borrow token is different from supply token
        if (pools[borrowIndex] == _supplyPoolToken) {
            if (borrowIndex == 0) {
                borrowIndex = pools.length - 1;
            } else {
                borrowIndex--;
            }
        }

        address underlying = IAToken(pools[borrowIndex]).UNDERLYING_ASSET_ADDRESS();
        emit log_named_string("borrow", ERC20(underlying).symbol());

        return Asset(0, pools[borrowIndex], underlying);
    }

    /**
     * @dev Returns the supply and borrow asset, checking for threshold and borrow threshold.
     * @dev The borrow amount is set to the maximum borrowable minus 10%.
     * @notice A direct deposit is done to AAVE to ensure enough liquidity to borrow.
     * @param _amount    amount
     * @param _supplyIndex   index of pool token supply
     * @param _borrowIndex   index of pool token borrow
     */
    function getAssets(
        uint256 _amount,
        uint8 _supplyIndex,
        uint8 _borrowIndex
    ) internal returns (Asset memory, Asset memory) {
        Asset memory supply = getSupplyAsset(_amount, _supplyIndex, false);
        Asset memory borrow = getBorrowAsset(_borrowIndex, supply.poolToken);

        // Adjust the amount so that borrow amount > threshold
        uint256 threshold = positionsManager.threshold(borrow.poolToken);
        borrow.amount =
            (getMaxToBorrow(supply.amount, supply.underlying, borrow.underlying) * 90) /
            100;
        if (borrow.amount < threshold) {
            supply.amount += (supply.amount * threshold) / borrow.amount;
            borrow.amount += threshold;
        }

        // Ensure enough liquidity in Aave
        supplier3.approve(borrow.underlying, address(lendingPool), borrow.amount);
        supplier3.deposit(borrow.underlying, borrow.amount);

        emit log_named_decimal_uint(
            "supply.amount",
            supply.amount,
            ERC20(supply.underlying).decimals()
        );
        emit log_named_decimal_uint(
            "borrow.amount",
            borrow.amount,
            ERC20(borrow.underlying).decimals()
        );

        return (supply, borrow);
    }

    /**
     * @dev AssertEq with a tolerance of 1 wei
     * @param _value value to check
     * @param _expected expected value
     * @param _msg debug message
     */
    function assertEqNear(
        uint256 _value,
        uint256 _expected,
        string memory _msg
    ) internal {
        assertLe(getAbsDiff(_value, _expected), 1, _msg);
    }

    /**
     * @dev Returns the value of `_amount` token unit in another unit.
     * @param _amount value of source token
     * @param _sourceUnderlying unit of source token
     * @param _targetUnderlying unit of target token
     */
    function getValueOfIn(
        uint256 _amount,
        address _sourceUnderlying,
        address _targetUnderlying
    ) internal returns (uint256) {
        uint256 sourcePrice = oracle.getAssetPrice(_sourceUnderlying);
        uint256 targetPrice = oracle.getAssetPrice(_targetUnderlying);

        uint256 amount = (((_amount * sourcePrice) / targetPrice) *
            10**ERC20(_targetUnderlying).decimals()) / 10**ERC20(_sourceUnderlying).decimals();

        return amount;
    }

    /**
     * @dev Returns the maximum to borrow providing `_amount`of supply token.
     * @notice The result is in borrow underlying token unit.
     * @param _amount amount of supplied token
     * @param _supplyUnderlying supply underlying
     * @param _borrowUnderlying borrow underlying
     */
    function getMaxToBorrow(
        uint256 _amount,
        address _supplyUnderlying,
        address _borrowUnderlying
    ) internal returns (uint256) {
        uint256 amount = getValueOfIn(_amount, _supplyUnderlying, _borrowUnderlying);

        (, , uint256 liquidationThreshold, , , , , , , ) = protocolDataProvider
        .getReserveConfigurationData(_supplyUnderlying);

        return (amount * liquidationThreshold) / PERCENT_BASE;
    }
}
