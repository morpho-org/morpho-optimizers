// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import {ILendingPool} from "@contracts/aave-v2/interfaces/aave/ILendingPool.sol";
import {IPriceOracleGetter} from "@contracts/aave-v2/interfaces/aave/IPriceOracleGetter.sol";
import {IAaveIncentivesController} from "@contracts/aave-v2/interfaces/aave/IAaveIncentivesController.sol";
import {ILendingPoolAddressesProvider} from "@contracts/aave-v2/interfaces/aave/ILendingPoolAddressesProvider.sol";
import {IIncentivesVault} from "@contracts/aave-v2/interfaces/IIncentivesVault.sol";
import {IEntryPositionsManager} from "@contracts/aave-v2/interfaces/IEntryPositionsManager.sol";
import {IExitPositionsManager} from "@contracts/aave-v2/interfaces/IExitPositionsManager.sol";
import {IInterestRatesManager} from "@contracts/aave-v2/interfaces/IInterestRatesManager.sol";
import {IRewardsManager} from "@contracts/aave-v2/interfaces/IRewardsManager.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Lens} from "@contracts/aave-v2/lens/Lens.sol";
import {Morpho} from "@contracts/aave-v2/Morpho.sol";
import {BaseConfig} from "../BaseConfig.sol";

contract Config is BaseConfig {
    address constant aAave = 0xFFC97d72E13E01096502Cb8Eb52dEe56f74DAD7B;
    address constant aDai = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    address constant aUsdc = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
    address constant aUsdt = 0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811;
    address constant aWbtc = 0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656;
    address constant aWeth = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e;

    address constant wrappedNativeToken = wEth;
    address constant aWrappedNativeToken = aWeth;

    address constant stableDebtDai = 0x778A13D3eeb110A4f7bb6529F99c000119a08E92;
    address constant variableDebtDai = 0x6C3c78838c761c6Ac7bE9F59fe808ea2A6E4379d;
    address constant variableDebtUsdc = 0x619beb58998eD2278e08620f97007e1116D5D25b;

    address constant swapRouterAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address public morphoDao = 0xcBa28b38103307Ec8dA98377ffF9816C164f9AFa;
    ILendingPoolAddressesProvider public poolAddressesProvider =
        ILendingPoolAddressesProvider(0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5);
    IAaveIncentivesController public aaveIncentivesController =
        IAaveIncentivesController(0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5);
    IPriceOracleGetter public oracle = IPriceOracleGetter(poolAddressesProvider.getPriceOracle());
    ILendingPool public pool = ILendingPool(poolAddressesProvider.getLendingPool());

    address public REWARD_TOKEN = aaveIncentivesController.REWARD_TOKEN();

    ProxyAdmin public proxyAdmin = ProxyAdmin(0x99917ca0426fbC677e84f873Fb0b726Bb4799cD8);

    TransparentUpgradeableProxy public lensProxy =
        TransparentUpgradeableProxy(payable(0x8706256509684E9cD93B7F19254775CE9324c226));
    TransparentUpgradeableProxy public morphoProxy =
        TransparentUpgradeableProxy(payable(0x777777c9898D384F785Ee44Acfe945efDFf5f3E0));
    TransparentUpgradeableProxy public rewardsManagerProxy;

    Lens public lensImplV1;
    Morpho public morphoImplV1;
    IRewardsManager public rewardsManagerImplV1;

    Lens public lens;
    Morpho public morpho;
    IRewardsManager public rewardsManager;
    IIncentivesVault public incentivesVault;
    IEntryPositionsManager public entryPositionsManager;
    IExitPositionsManager public exitPositionsManager;
    IInterestRatesManager public interestRatesManager;
}
