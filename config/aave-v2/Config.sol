// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ILendingPool} from "src/aave-v2/interfaces/aave/ILendingPool.sol";
import {IPriceOracleGetter} from "src/aave-v2/interfaces/aave/IPriceOracleGetter.sol";
import {ILendingPoolAddressesProvider} from "src/aave-v2/interfaces/aave/ILendingPoolAddressesProvider.sol";
import {IEntryPositionsManager} from "src/aave-v2/interfaces/IEntryPositionsManager.sol";
import {IExitPositionsManager} from "src/aave-v2/interfaces/IExitPositionsManager.sol";
import {IInterestRatesManager} from "src/aave-v2/interfaces/IInterestRatesManager.sol";
import {ILendingPoolConfigurator} from "test/aave-v2/helpers/ILendingPoolConfigurator.sol";
import {IMorpho} from "src/aave-v2/interfaces/IMorpho.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Lens} from "src/aave-v2/lens/Lens.sol";
import {Morpho} from "src/aave-v2/Morpho.sol";
import {BaseConfig} from "../BaseConfig.sol";

contract Config is BaseConfig {
    address constant aAave = 0xFFC97d72E13E01096502Cb8Eb52dEe56f74DAD7B;
    address constant aDai = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    address constant aUsdc = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
    address constant aUsdt = 0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811;
    address constant aWbtc = 0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656;
    address constant aWeth = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e;
    address constant aCrv = 0x8dAE6Cb04688C62d939ed9B68d32Bc62e49970b1;
    address constant aStEth = 0x1982b2F5814301d4e9a8b0201555376e62F82428;
    address constant aFrax = 0xd4937682df3C8aEF4FE912A96A74121C0829E664;

    address constant wrappedNativeToken = wEth;
    address constant aWrappedNativeToken = aWeth;

    address constant stableDebtDai = 0x778A13D3eeb110A4f7bb6529F99c000119a08E92;
    address constant variableDebtDai = 0x6C3c78838c761c6Ac7bE9F59fe808ea2A6E4379d;
    address constant variableDebtUsdc = 0x619beb58998eD2278e08620f97007e1116D5D25b;

    address constant swapRouterAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    ILendingPoolAddressesProvider public poolAddressesProvider =
        ILendingPoolAddressesProvider(0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5);
    ILendingPoolConfigurator public lendingPoolConfigurator =
        ILendingPoolConfigurator(0x311Bb771e4F8952E6Da169b425E7e92d6Ac45756);
    IPriceOracleGetter public oracle = IPriceOracleGetter(poolAddressesProvider.getPriceOracle());
    ILendingPool public pool = ILendingPool(poolAddressesProvider.getLendingPool());

    ProxyAdmin public proxyAdmin = ProxyAdmin(0x99917ca0426fbC677e84f873Fb0b726Bb4799cD8);

    TransparentUpgradeableProxy public lensProxy =
        TransparentUpgradeableProxy(payable(0x507fA343d0A90786d86C7cd885f5C49263A91FF4));
    TransparentUpgradeableProxy public morphoProxy =
        TransparentUpgradeableProxy(payable(0x777777c9898D384F785Ee44Acfe945efDFf5f3E0));

    Lens public lensImplV1;
    Morpho public morphoImplV1;

    Lens public lens;
    Morpho public morpho;
    IEntryPositionsManager public entryPositionsManager;
    IExitPositionsManager public exitPositionsManager;
    IInterestRatesManager public interestRatesManager;
}
