// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "src/compound/interfaces/IRewardsManager.sol";
import "src/compound/interfaces/IInterestRatesManager.sol";
import "src/compound/interfaces/IPositionsManager.sol";
import "src/compound/interfaces/compound/ICompound.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {RewardsManager} from "src/compound/RewardsManager.sol";
import {InterestRatesManager} from "src/compound/InterestRatesManager.sol";
import {PositionsManager} from "src/compound/PositionsManager.sol";
import {Morpho} from "src/compound/Morpho.sol";
import {Lens} from "src/compound/lens/Lens.sol";

import "config/compound/Config.sol";
import "forge-std/Script.sol";

contract Deploy is Script, Config {
    ProxyAdmin public proxyAdmin;

    Lens public lens;
    Morpho public morpho;
    IPositionsManager public positionsManager;
    IInterestRatesManager public interestRatesManager;
    RewardsManager public rewardsManager;

    function run() external {
        vm.label(comptroller, "Comptroller");
        vm.label(cDai, "cDAI");
        vm.label(cEth, "cETH");
        vm.label(cUsdc, "cUSDC");
        vm.label(cWbtc2, "cWBTC");
        vm.label(cBat, "cBAT");
        vm.label(wEth, "WETH");

        vm.startBroadcast();

        proxyAdmin = new ProxyAdmin();

        // Deploy Morpho's dependencies
        interestRatesManager = new InterestRatesManager();
        positionsManager = new PositionsManager();

        // Deploy Morpho
        Morpho morphoImpl = new Morpho();
        TransparentUpgradeableProxy morphoProxy = new TransparentUpgradeableProxy(
            address(morphoImpl),
            address(proxyAdmin),
            abi.encodeWithSelector(
                morphoImpl.initialize.selector,
                positionsManager,
                interestRatesManager,
                comptroller,
                defaultMaxGasForMatching,
                1,
                defaultMaxSortedUsers,
                cEth,
                wEth
            )
        );
        morpho = Morpho(payable(morphoProxy));

        // Deploy RewardsManager
        RewardsManager rewardsManagerImpl = new RewardsManager();

        TransparentUpgradeableProxy rewardsManagerProxy = new TransparentUpgradeableProxy(
            address(rewardsManagerImpl),
            address(proxyAdmin),
            abi.encodeWithSelector(rewardsManagerImpl.initialize.selector, address(morpho))
        );
        rewardsManager = RewardsManager(address(rewardsManagerProxy));

        morpho.setRewardsManager(IRewardsManager(address(rewardsManager)));

        // Deploy Lens
        Lens lensImpl = new Lens(address(morpho));
        TransparentUpgradeableProxy lensProxy = new TransparentUpgradeableProxy(
            address(lensImpl),
            address(proxyAdmin),
            abi.encodeWithSelector(lensImpl.initialize.selector, address(morpho))
        );
        lens = Lens(address(lensProxy));

        // Create markets
        Types.MarketParameters memory defaultMarketParameters = Types.MarketParameters({
            reserveFactor: 0,
            p2pIndexCursor: 3333
        });
        morpho.createMarket(cDai, defaultMarketParameters);
        morpho.createMarket(cUsdc, defaultMarketParameters);
        morpho.createMarket(cEth, defaultMarketParameters);
        morpho.createMarket(cWbtc2, defaultMarketParameters);
        morpho.createMarket(cBat, defaultMarketParameters);

        vm.stopBroadcast();
    }
}
