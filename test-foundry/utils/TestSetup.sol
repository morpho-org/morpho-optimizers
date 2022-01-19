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

    function setNMAXAndCreateSigners(uint16 _NMAX) internal {
        marketsManager.setNmaxForMatchingEngine(_NMAX);

        while (borrowers.length < _NMAX) {
            borrowers.push(new User(positionsManager, marketsManager));
            writeBalanceOf(address(borrowers[borrowers.length - 1]), dai, type(uint256).max / 2);
            writeBalanceOf(address(borrowers[borrowers.length - 1]), usdc, type(uint256).max / 2);

            suppliers.push(new User(positionsManager, marketsManager));
            writeBalanceOf(address(suppliers[suppliers.length - 1]), dai, type(uint256).max / 2);
            writeBalanceOf(address(suppliers[suppliers.length - 1]), usdc, type(uint256).max / 2);
        }
    }

    function testEquality(uint256 _firstValue, uint256 _secondValue) internal {
        assertLe(getAbsDiff(_firstValue, _secondValue), 15);
    }

    /**
     * @dev Returns an amount which is greater than the supplied asset threshold
     * @param _amount    amount of asset
     * @param _supplyAsset   aToken address
     */
    function getSupplyAmount(uint256 _amount, address _supplyAsset) internal returns (uint256) {
        //_amount = _amount % 150_000_000 ether;
        if (_amount > 150_000_000 ether) {
            _amount = 150_000_000 ether;
        }

        // Check that amount is greater than threshold
        uint256 threshold = positionsManager.threshold(_supplyAsset);
        address underlying = IAToken(_supplyAsset).UNDERLYING_ASSET_ADDRESS();
        if (denormalizeAmount(_amount, underlying) < threshold) {
            _amount += normalizeAmount(threshold, underlying);
        }

        return _amount;
    }

    function denormalizeAmount(uint256 _amount, address _erc20) internal view returns (uint256) {
        uint256 decimals = ERC20(_erc20).decimals();

        return decimals == 18 ? _amount : _amount >> (18 - decimals);
    }

    function normalizeAmount(uint256 _amount, address _erc20) internal view returns (uint256) {
        uint256 decimals = ERC20(_erc20).decimals();

        return decimals == 18 ? _amount : _amount << (18 - decimals);
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

        Asset memory asset = Asset(0, pools[index], underlying);

        asset.amount = denormalizeAmount(
            getSupplyAmount(_amount, asset.poolToken),
            asset.underlying
        );

        return asset;
    }

    /**
     * @dev Returns the amount, pool token address and underlying address of a borrowed asset.
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
     * @dev Returns the supply and borrow asset, checking for threshold and borrow threshold
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
        borrow.amount = getMaxToBorrow(
            denormalizeAmount(supply.amount, supply.underlying),
            supply.poolToken,
            borrow.poolToken
        );
        if (borrow.amount < threshold) {
            supply.amount *= 10; // TODO more accurate calculation
            borrow.amount = threshold;
        }

        // Ensure enough liquidity in Aave
        supplier3.approve(borrow.underlying, address(lendingPool), borrow.amount);
        supplier3.deposit(borrow.underlying, borrow.amount);

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
     * @dev Returns the maximum to borrow providing `_amount`of supply token.
     * @param _amount amount of supplied token
     * @param _suppliedPoolToken supply pool token
     * @param _borrowedPoolToken borrow pool token
     */
    function getMaxToBorrow(
        uint256 _amount,
        address _suppliedPoolToken,
        address _borrowedPoolToken
    ) internal returns (uint256) {
        uint256 underlyingPrice = oracle.getAssetPrice(
            IAToken(_suppliedPoolToken).UNDERLYING_ASSET_ADDRESS()
        );

        (
            uint256 reserveDecimals,
            ,
            uint256 liquidationThreshold,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = protocolDataProvider.getReserveConfigurationData(
            IAToken(_borrowedPoolToken).UNDERLYING_ASSET_ADDRESS()
        );

        uint256 tokenUnit = 10**reserveDecimals;
        uint256 collateralToAdd = (_amount * underlyingPrice) / tokenUnit;
        uint256 maxDebtValue = (collateralToAdd * liquidationThreshold) / PERCENT_BASE;

        return maxDebtValue;
    }
}
