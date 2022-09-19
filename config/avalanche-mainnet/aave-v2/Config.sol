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
    address constant aave = 0x63a72806098Bd3D9520cC43356dD78afe5D386D9;
    address constant dai = 0xd586E7F844cEa2F87f50152665BCbc2C279D8d70;
    address constant usdc = 0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664;
    address constant usdt = 0xc7198437980c041c805A1EDcbA50c1Ce5db95118;
    address constant wbtc = 0x50b7545627a5162F82A992c33b87aDc75187B218;
    address constant wEth = 0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB;
    address constant wavax = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address constant stEth = address(0);

    address constant aAave = 0xD45B7c061016102f9FA220502908f2c0f1add1D7;
    address constant aDai = 0x47AFa96Cdc9fAb46904A55a6ad4bf6660B53c38a;
    address constant aUsdc = 0x46A51127C3ce23fb7AB1DE06226147F446e4a857;
    address constant aUsdt = 0x532E6537FEA298397212F09A61e03311686f548e;
    address constant aWbtc = 0x686bEF2417b6Dc32C50a3cBfbCC3bb60E1e9a15D;
    address constant aWeth = 0x53f7c5869a859F0AeC3D334ee8B4Cf01E3492f21;
    address constant avWavax = 0xDFE521292EcE2A4f44242efBcD66Bc594CA9714B;
    address constant aStEth = address(0);

    address constant wrappedNativeToken = wavax;
    address constant aWrappedNativeToken = avWavax;

    address constant stableDebtDai = 0x3676E4EE689D527dDb89812B63fAD0B7501772B3;
    address constant variableDebtDai = 0x1852DC24d1a8956a0B356AA18eDe954c7a0Ca5ae;
    address constant variableDebtUsdc = 0x848c080d2700CBE1B894a3374AD5E887E5cCb89c;

    address constant stEthWhale = address(0);
    address constant stEthWhale2 = address(0);

    address constant swapRouterAddress = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4;

    address public morphoDao;
    ILendingPoolAddressesProvider public poolAddressesProvider =
        ILendingPoolAddressesProvider(0xb6A86025F0FE1862B372cb0ca18CE3EDe02A318f);
    IAaveIncentivesController public aaveIncentivesController =
        IAaveIncentivesController(0x01D83Fe6A10D2f2B7AF17034343746188272cAc9);
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
