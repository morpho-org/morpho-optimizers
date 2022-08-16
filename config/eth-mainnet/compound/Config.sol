// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/compound/interfaces/compound/ICompound.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";

import {RewardsManager} from "@contracts/compound/RewardsManager.sol";
import {PositionsManager} from "@contracts/compound/PositionsManager.sol";
import {InterestRatesManager} from "@contracts/compound/InterestRatesManager.sol";
import {IncentivesVault} from "@contracts/compound/IncentivesVault.sol";
import {Lens} from "@contracts/compound/lens/Lens.sol";
import {Morpho} from "@contracts/compound/Morpho.sol";

contract Config {
    address constant aave = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address constant dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant wEth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant comp = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address constant bat = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF;
    address constant tusd = 0x0000000000085d4780B73119b644AE5ecd22b376;
    address constant uni = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address constant zrx = 0xE41d2489571d322189246DaFA5ebDe1F4699F498;
    address constant link = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address constant mkr = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address constant fei = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA;
    address constant yfi = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address constant usdp = 0x8E870D67F660D95d5be530380D0eC0bd388289E1;
    address constant sushi = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;

    address constant cAave = 0xe65cdB6479BaC1e22340E4E755fAE7E509EcD06c;
    address constant cDai = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address constant cUsdc = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address constant cUsdt = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9;
    address constant cWbtc2 = 0xccF4429DB6322D5C611ee964527D42E5d685DD6a;
    address constant cEth = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address constant cBat = 0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E;
    address constant cTusd = 0x12392F67bdf24faE0AF363c24aC620a2f67DAd86;
    address constant cUni = 0x35A18000230DA775CAc24873d00Ff85BccdeD550;
    address constant cComp = 0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4;
    address constant cZrx = 0xB3319f5D18Bc0D84dD1b4825Dcde5d5f7266d407;
    address constant cLink = 0xFAce851a4921ce59e912d19329929CE6da6EB0c7;
    address constant cMkr = 0x95b4eF2869eBD94BEb4eEE400a99824BF5DC325b;
    address constant cFei = 0x7713DD9Ca933848F6819F38B8352D9A15EA73F67;
    address constant cYfi = 0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946;
    address constant cUsdp = 0x041171993284df560249B57358F931D9eB7b925D;
    address constant cSushi = 0x4B0181102A0112A2ef11AbEE5563bb4a3176c9d7;

    address public morphoDao = 0xcBa28b38103307Ec8dA98377ffF9816C164f9AFa;
    IComptroller public comptroller = IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    ProxyAdmin public proxyAdmin = ProxyAdmin(0x99917ca0426fbC677e84f873Fb0b726Bb4799cD8);
    TransparentUpgradeableProxy public lensProxy =
        TransparentUpgradeableProxy(payable(0x930f1b46e1D081Ec1524efD95752bE3eCe51EF67));
    TransparentUpgradeableProxy public morphoProxy =
        TransparentUpgradeableProxy(payable(0x8888882f8f843896699869179fB6E4f7e3B58888));
    TransparentUpgradeableProxy public rewardsManagerProxy =
        TransparentUpgradeableProxy(payable(0x78681e63b6f3ad81ecD64AECC404d765b529C80d));

    Lens public lensImplV1;
    Morpho public morphoImplV1;
    RewardsManager public rewardsManagerImplV1;

    Lens public lens;
    Morpho public morpho;
    RewardsManager public rewardsManager;
    IncentivesVault public incentivesVault;
    PositionsManager public positionsManager;
    InterestRatesManager public interestRatesManager;
}
