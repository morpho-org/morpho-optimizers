// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "ds-test/test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../PositionsManagerForAave.sol";
import "../MarketsManagerForAave.sol";

import "@config/Config.sol";
import "./HEVM.sol";
import "./Utils.sol";
import "./SimplePriceOracle.sol";
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
        // All token added with createMarket must be added in create_custom_price_oracle function.
        marketsManager.createMarket(aDai, WAD, type(uint256).max);
        marketsManager.createMarket(aUsdc, to6Decimals(WAD), type(uint256).max);
        marketsManager.createMarket(aWbtc, 10**4, type(uint256).max);
        marketsManager.createMarket(aUsdt, to6Decimals(WAD), type(uint256).max);
        marketsManager.createMarket(aWmatic, WAD, type(uint256).max);

        for (uint256 i = 0; i < 3; i++) {
            suppliers.push(new User(positionsManager, marketsManager));

            write_balanceOf(address(suppliers[i]), dai, type(uint256).max / 2);
            write_balanceOf(address(suppliers[i]), usdc, type(uint256).max / 2);
        }
        supplier1 = suppliers[0];
        supplier2 = suppliers[1];
        supplier3 = suppliers[2];

        for (uint256 i = 0; i < 3; i++) {
            borrowers.push(new User(positionsManager, marketsManager));

            write_balanceOf(address(borrowers[i]), dai, type(uint256).max / 2);
            write_balanceOf(address(borrowers[i]), usdc, type(uint256).max / 2);
        }
        borrower1 = borrowers[0];
        borrower2 = borrowers[1];
        borrower3 = borrowers[2];
    }

    function write_balanceOf(
        address who,
        address acct,
        uint256 value
    ) internal {
        hevm.store(acct, keccak256(abi.encode(who, slots[acct])), bytes32(value));
    }

    function mine_blocks(uint256 _count) internal {
        hevm.roll(block.number + _count);
        hevm.warp(block.timestamp + _count * 1000 * AVERAGE_BLOCK_TIME);
    }

    function range(uint256 _amount, address _pool) internal view returns (uint256) {
        return range(_amount, _pool, 1);
    }

    function range(
        uint256 _amount,
        address _pool,
        uint256 div
    ) internal view returns (uint256) {
        _amount %= type(uint64).max / div;
        if (_amount <= positionsManager.threshold(_pool))
            _amount += positionsManager.threshold(_pool);

        return _amount;
    }

    function setNMAXAndCreateSigners(uint16 _NMAX) internal {
        marketsManager.setMaxNumberOfUsersInTree(_NMAX);

        while (borrowers.length < _NMAX) {
            borrowers.push(new User(positionsManager, marketsManager));
            write_balanceOf(address(borrowers[borrowers.length - 1]), dai, type(uint256).max / 2);
            write_balanceOf(address(borrowers[borrowers.length - 1]), usdc, type(uint256).max / 2);

            suppliers.push(new User(positionsManager, marketsManager));
            write_balanceOf(address(suppliers[suppliers.length - 1]), dai, type(uint256).max / 2);
            write_balanceOf(address(suppliers[suppliers.length - 1]), usdc, type(uint256).max / 2);
        }
    }

    function testEquality(uint256 _firstValue, uint256 _secondValue) internal {
        assertLe(get_abs_diff(_firstValue, _secondValue), 15);
    }
}
