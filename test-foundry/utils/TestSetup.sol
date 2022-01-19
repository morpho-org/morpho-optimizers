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

            writeBalanceOf(address(suppliers[i]), dai, type(uint256).max / 2);
            writeBalanceOf(address(suppliers[i]), usdc, type(uint256).max / 2);
        }
        supplier1 = suppliers[0];
        supplier2 = suppliers[1];
        supplier3 = suppliers[2];

        for (uint256 i = 0; i < 3; i++) {
            borrowers.push(new User(positionsManager, marketsManager));

            writeBalanceOf(address(borrowers[i]), dai, type(uint256).max / 2);
            writeBalanceOf(address(borrowers[i]), usdc, type(uint256).max / 2);
        }
        borrower1 = borrowers[0];
        borrower2 = borrowers[1];
        borrower3 = borrowers[2];
    }

    function writeBalanceOf(
        address who,
        address acct,
        uint256 value
    ) internal {
        hevm.store(acct, keccak256(abi.encode(who, slots[acct])), bytes32(value));
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
}
