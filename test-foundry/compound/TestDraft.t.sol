// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./setup/TestSetup.sol";
import "hardhat/console.sol";

contract TestDraft is TestSetup {
    function test_cTokenAmount() public {
        uint256 amount = 5000 ether;

        // Supply 1000 USDC
        supplier1.approve(usdc, to6Decimals(amount));
        supplier1.supply(cUsdc, to6Decimals(amount));

        // Supply 1000 DAI
        supplier2.approve(dai, amount);
        supplier2.supply(cDai, amount);

        ICToken cDaiToken = ICToken(cDai);
        ICToken cUsdcToken = ICToken(cUsdc);

        // Print balance of cDai & cUsdc of Position Manager
        console.log(
            "Amount of cUsdc - Positions Manager",
            cUsdcToken.balanceOf(address(positionsManager))
        );
        console.log(
            "Amount of cDai - Positions Manager",
            cDaiToken.balanceOf(address(positionsManager))
        );
        console.log("");

        // Print USDC balance of supplier1
        (uint256 inP2PSupplier1, uint256 onPoolSupplier1) = positionsManager.supplyBalanceInOf(
            cUsdc,
            address(supplier1)
        );

        console.log("Amount of USDC inP2P - Supplier 1", inP2PSupplier1);
        console.log("Amount of USDC onPool - Supplier 1", onPoolSupplier1);
        console.log("");

        // Print DAI balance of supplier2
        (uint256 inP2PSupplier2, uint256 onPoolSupplier2) = positionsManager.supplyBalanceInOf(
            cDai,
            address(supplier2)
        );

        console.log("Amount of DAI inP2P - Supplier 2", inP2PSupplier2);
        console.log("Amount of DAI onPool - Supplier 2", onPoolSupplier2);
        console.log("");

        // Amount of USDC according to Compound
        console.log(
            "Amount of USDC - Compound's value",
            cUsdcToken.balanceOfUnderlying(address(positionsManager))
        );
        console.log("");

        // Amount of DAI according to Compound
        console.log(
            "Amount of DAI - Compound's value",
            cDaiToken.balanceOfUnderlying(address(positionsManager))
        );
        console.log("");
    }
}
