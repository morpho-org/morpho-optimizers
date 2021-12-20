// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

// Display logs:
// emit log_named_<type>("comarketsManagerentaire", value);
// Example:
// emit log_named_uint("supplier1", IERC20(usdc).balanceOf(address(supplier1)));

import "ds-test/test.sol";

import "../PositionsManagerForAave.sol";
import "../MarketsManagerForAave.sol";

import "@config/Config.sol";
import "./SimplePriceOracle.sol";
import "./HEVM.sol";
import "./User.sol";

contract MarketsManagerForAaveTest is DSTest, Config {
    HEVM hevm = HEVM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    PositionsManagerForAave internal positionsManager;
    MarketsManagerForAave internal marketsManager;

    ILendingPoolAddressesProvider lendingPoolAddressesProvider;
    ILendingPool lendingPool;

    User supplier1;
    User borrower1;

    function setUp() public {
        marketsManager = new MarketsManagerForAave(lendingPoolAddressesProviderAddress);
        positionsManager = new PositionsManagerForAave(
            address(marketsManager),
            lendingPoolAddressesProviderAddress
        );

        lendingPoolAddressesProvider = ILendingPoolAddressesProvider(
            lendingPoolAddressesProviderAddress
        );
        lendingPool = ILendingPool(lendingPoolAddressesProvider.getLendingPool());

        marketsManager.setPositionsManager(address(positionsManager));
        marketsManager.setLendingPool();
        marketsManager.createMarket(aDai, 10**6, type(uint256).max);
        marketsManager.createMarket(aUsdc, 10**6, type(uint256).max);

        supplier1 = new User(positionsManager, marketsManager);
        borrower1 = new User(positionsManager, marketsManager);

        write_balanceOf(address(supplier1), dai, 1 ether);
        write_balanceOf(address(borrower1), dai, 1 ether);
        write_balanceOf(address(borrower1), usdc, 1 ether);
    }

    function write_balanceOf(
        address who,
        address acct,
        uint256 value
    ) internal {
        // !!! "0" value is the SLOT, which depends on the token / network !!!
        // A tool to find the slot of tokens' balance: https://github.com/kendricktan/slot20
        hevm.store(acct, keccak256(abi.encode(who, slots[acct])), bytes32(value));
    }

    // Suppliers on Aave (no borrowers) >> Should have correct balances at the beginning
    function test_borrowers_have_correct_balance_at_start() public {
        (uint256 onPool, uint256 inP2P) = positionsManager.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        assertEq(onPool, 0);
        assertEq(inP2P, 0);
    }

    // Suppliers on Aave (no borrowers) >> Should revert when providing 0 as collateral
    function testFail_revert_when_providing_0_as_collateral() public {
        supplier1.supply(aDai, 0);
    }

    // Fuzzing
    // Suppliers on Aave (no borrowers) >> Should have the correct balances after supply
    function test_correct_balance_after_supply(uint16 _amount) public {
        if (_amount <= positionsManager.threshold(aDai)) return;

        uint256 daiBalanceBefore = IERC20(dai).balanceOf(address(borrower1));
        uint256 expectedDaiBalanceAfter = daiBalanceBefore - _amount;

        borrower1.approve(dai, address(positionsManager), _amount);
        borrower1.supply(aDai, _amount);

        uint256 daiBalanceAfter = IERC20(dai).balanceOf(address(borrower1));
        assertEq(daiBalanceAfter, expectedDaiBalanceAfter);

        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(usdc);
        uint256 expectedSupplyBalanceOnPool = underlyingToScaledBalance(_amount, normalizedIncome);

        assertEq(IERC20(aDai).balanceOf(address(positionsManager)), _amount);
        (uint256 onPool, uint256 inP2P) = positionsManager.supplyBalanceInOf(
            aUsdc,
            address(positionsManager)
        );
        assertEq(onPool, expectedSupplyBalanceOnPool);
        assertEq(inP2P, 0);
    }

    /*
    function test_liquidation() public {
        // Set lendingPoolAddressesProvider owner to this contract
        hevm.store(address(lendingPoolAddressesProvider), bytes32(0), bytes32(uint256(uint160(address(this)))));
        SimplePriceOracle oracle = new SimplePriceOracle();
        lendingPoolAddressesProvider.setPriceOracle(priceOracle);

        uint256 amount = 100 * 10**6;
        borrower1.approve(usdc, positionsManager, amount);
        borrower1.supply(aUsdc, amount);
        (uint256 collateralBalanceInScaledBalance, ) = positionsManager.supplyBalanceInOf(aUsdc, address(borrower1));
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(usdc);
        uint256 collateralBalanceInUnderlying = scaledBalanceToUnderlying(collateralBalanceInScaledBalance, normalizedIncome);
    }
*/

    function underlyingToScaledBalance(uint256 _scaledBalance, uint256 _normalizedIncome)
        internal
        pure
        returns (uint256)
    {
        return (_scaledBalance * 1e27) / _normalizedIncome;
    }
}
