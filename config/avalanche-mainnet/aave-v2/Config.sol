// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

contract Config {
    address aave = 0x63a72806098Bd3D9520cC43356dD78afe5D386D9;
    address dai = 0xd586E7F844cEa2F87f50152665BCbc2C279D8d70;
    address usdc = 0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664;
    address usdt = 0xc7198437980c041c805A1EDcbA50c1Ce5db95118;
    address wbtc = 0x50b7545627a5162F82A992c33b87aDc75187B218;
    address wEth = 0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB;
    address wavax = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    address aAave = 0xD45B7c061016102f9FA220502908f2c0f1add1D7;
    address aDai = 0x47AFa96Cdc9fAb46904A55a6ad4bf6660B53c38a;
    address aUsdc = 0x46A51127C3ce23fb7AB1DE06226147F446e4a857;
    address aUsdt = 0x532E6537FEA298397212F09A61e03311686f548e;
    address aWbtc = 0x686bEF2417b6Dc32C50a3cBfbCC3bb60E1e9a15D;
    address aWeth = 0x53f7c5869a859F0AeC3D334ee8B4Cf01E3492f21;
    address avWavax = 0xDFE521292EcE2A4f44242efBcD66Bc594CA9714B;

    address stableDebtDai = 0x3676E4EE689D527dDb89812B63fAD0B7501772B3;
    address variableDebtDai = 0x1852DC24d1a8956a0B356AA18eDe954c7a0Ca5ae;
    address variableDebtUsdc = 0x848c080d2700CBE1B894a3374AD5E887E5cCb89c;

    address lendingPoolAddressesProviderAddress = 0xb6A86025F0FE1862B372cb0ca18CE3EDe02A318f;
    address protocolDataProviderAddress = 0x65285E9dfab318f57051ab2b139ccCf232945451;
    address aaveIncentivesControllerAddress = 0x01D83Fe6A10D2f2B7AF17034343746188272cAc9;
    address swapRouterAddress = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4;

    uint24 MORPHO_UNIV3_FEE = 3000;
    uint24 REWARD_UNIV3_FEE = 3000;
}
