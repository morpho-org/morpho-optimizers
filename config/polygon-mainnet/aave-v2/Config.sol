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

contract Config {
    address constant aave = 0xD6DF932A45C0f255f85145f286eA0b292B21C90B;
    address constant dai = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address constant usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address constant usdt = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address constant wbtc = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;
    address constant wEth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address constant wmatic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    address constant aAave = 0x1d2a0E5EC8E5bBDCA5CB219e649B565d8e5c3360;
    address constant aDai = 0x27F8D03b3a2196956ED754baDc28D73be8830A6e;
    address constant aUsdc = 0x1a13F4Ca1d028320A707D99520AbFefca3998b7F;
    address constant aUsdt = 0x60D55F02A771d515e077c9C2403a1ef324885CeC;
    address constant aWbtc = 0x5c2ed810328349100A66B82b78a1791B101C9D61;
    address constant aWeth = 0x28424507fefb6f7f8E9D3860F56504E4e5f5f390;
    address constant aWmatic = 0x8dF3aad3a84da6b69A4DA8aeC3eA40d9091B2Ac4;

    address constant wrappedNativeToken = wmatic;
    address constant aWrappedNativeToken = aWmatic;

    address constant stableDebtDai = 0x2238101B7014C279aaF6b408A284E49cDBd5DB55;
    address constant variableDebtDai = 0x75c4d1Fb84429023170086f06E682DcbBF537b7d;
    address constant variableDebtUsdc = 0x248960A9d75EdFa3de94F7193eae3161Eb349a12;

    address constant swapRouterAddress = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address public morphoDao;
    ILendingPoolAddressesProvider public poolAddressesProvider =
        ILendingPoolAddressesProvider(0xd05e3E715d945B59290df0ae8eF85c1BdB684744);
    IAaveIncentivesController public aaveIncentivesController =
        IAaveIncentivesController(0x357D51124f59836DeD84c8a1730D72B749d8BC23);
    IPriceOracleGetter public oracle = IPriceOracleGetter(poolAddressesProvider.getPriceOracle());
    ILendingPool public pool = ILendingPool(poolAddressesProvider.getLendingPool());

    address public REWARD_TOKEN = aaveIncentivesController.REWARD_TOKEN();

    ProxyAdmin public proxyAdmin;

    TransparentUpgradeableProxy public lensProxy;
    TransparentUpgradeableProxy public morphoProxy;
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
