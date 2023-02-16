// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import "src/compound/interfaces/compound/ICompound.sol";
import {IPositionsManager} from "src/compound/interfaces/IPositionsManager.sol";
import {IInterestRatesManager} from "src/compound/interfaces/IInterestRatesManager.sol";
import {IMorpho} from "src/compound/interfaces/IMorpho.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {RewardsManager} from "src/compound/RewardsManager.sol";
import {LensExtension} from "src/compound/lens/LensExtension.sol";
import {Lens} from "src/compound/lens/Lens.sol";
import {Morpho} from "src/compound/Morpho.sol";
import {BaseConfig} from "../BaseConfig.sol";

contract Config is BaseConfig {
    address constant cAave = 0xe65cdB6479BaC1e22340E4E755fAE7E509EcD06c;
    address constant cDai = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address constant cUsdc = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address constant cUsdt = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9;
    address constant cWbtc2 = 0xccF4429DB6322D5C611ee964527D42E5d685DD6a;
    address constant cEth = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address constant cComp = 0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4;
    address constant cBat = 0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E;
    address constant cTusd = 0x12392F67bdf24faE0AF363c24aC620a2f67DAd86;
    address constant cUni = 0x35A18000230DA775CAc24873d00Ff85BccdeD550;
    address constant cZrx = 0xB3319f5D18Bc0D84dD1b4825Dcde5d5f7266d407;
    address constant cLink = 0xFAce851a4921ce59e912d19329929CE6da6EB0c7;
    address constant cMkr = 0x95b4eF2869eBD94BEb4eEE400a99824BF5DC325b;
    address constant cFei = 0x7713DD9Ca933848F6819F38B8352D9A15EA73F67;
    address constant cYfi = 0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946;
    address constant cUsdp = 0x041171993284df560249B57358F931D9eB7b925D;
    address constant cSushi = 0x4B0181102A0112A2ef11AbEE5563bb4a3176c9d7;

    IComptroller public comptroller = IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
    ICompoundOracle public oracle = ICompoundOracle(comptroller.oracle());

    ProxyAdmin public proxyAdmin = ProxyAdmin(0x99917ca0426fbC677e84f873Fb0b726Bb4799cD8);

    TransparentUpgradeableProxy public lensProxy =
        TransparentUpgradeableProxy(payable(0x930f1b46e1D081Ec1524efD95752bE3eCe51EF67));
    TransparentUpgradeableProxy public morphoProxy =
        TransparentUpgradeableProxy(payable(0x8888882f8f843896699869179fB6E4f7e3B58888));
    TransparentUpgradeableProxy public rewardsManagerProxy;

    Lens public lensImplV1;
    Morpho public morphoImplV1;
    RewardsManager public rewardsManagerImplV1;

    Lens public lens;
    LensExtension public lensExtension;

    Morpho public morpho;
    RewardsManager public rewardsManager;
    IPositionsManager public positionsManager;
    IInterestRatesManager public interestRatesManager;
}
