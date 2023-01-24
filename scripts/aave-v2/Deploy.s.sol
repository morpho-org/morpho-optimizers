// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "src/aave-v2/interfaces/IInterestRatesManager.sol";
import "src/aave-v2/interfaces/IExitPositionsManager.sol";
import "src/aave-v2/interfaces/IEntryPositionsManager.sol";
import "src/aave-v2/interfaces/aave/ILendingPoolAddressesProvider.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {InterestRatesManager} from "src/aave-v2/InterestRatesManager.sol";
import {EntryPositionsManager} from "src/aave-v2/EntryPositionsManager.sol";
import {ExitPositionsManager} from "src/aave-v2/ExitPositionsManager.sol";
import {Morpho} from "src/aave-v2/Morpho.sol";
import {Lens} from "src/aave-v2/Lens.sol";

import "config/aave-v2/Config.sol";
import "forge-std/Script.sol";

contract Deploy is Script, Config {
    ProxyAdmin public proxyAdmin;

    Lens public lens;
    Morpho public morpho;
    IEntryPositionsManager public entryPositionsManager;
    IExitPositionsManager public exitPositionsManager;
    IInterestRatesManager public interestRatesManager;

    function run() external {
        vm.startBroadcast();

        proxyAdmin = new ProxyAdmin();

        // Deploy Morpho's dependencies
        entryPositionsManager = new EntryPositionsManager();
        exitPositionsManager = new ExitPositionsManager();
        interestRatesManager = new InterestRatesManager();

        // Deploy Morpho
        Morpho morphoImpl = new Morpho();
        TransparentUpgradeableProxy morphoProxy = new TransparentUpgradeableProxy(
            address(morphoImpl),
            address(proxyAdmin),
            abi.encodeWithSelector(
                morphoImpl.initialize.selector,
                entryPositionsManager,
                exitPositionsManager,
                interestRatesManager,
                lendingPoolAddressesProvider,
                defaultMaxGasForMatching,
                defaultMaxSortedUsers
            )
        );
        morpho = Morpho(address(morphoProxy));

        // Deploy Lens
        lens = new Lens(
            address(morpho),
            ILendingPoolAddressesProvider(lendingPoolAddressesProvider)
        );

        // Create markets
        Types.MarketParameters memory defaultMarketParameters = Types.MarketParameters({
            reserveFactor: 1000,
            p2pIndexCursor: 3333
        });
        morpho.createMarket(aave, defaultMarketParameters);
        morpho.createMarket(dai, defaultMarketParameters);
        morpho.createMarket(usdc, defaultMarketParameters);
        morpho.createMarket(usdt, defaultMarketParameters);
        morpho.createMarket(wbtc, defaultMarketParameters);
        morpho.createMarket(weth, defaultMarketParameters);
        morpho.createMarket(wmatic, defaultMarketParameters);

        vm.stopBroadcast();
    }
}
