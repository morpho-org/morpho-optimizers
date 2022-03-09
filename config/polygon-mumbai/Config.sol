// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

contract Config {
    address aave = 0x7e3d807Cb61745A75e375161E13970633B947356;
    address dai = 0xC87385b5E62099f92d490750Fcd6C901a524BBcA;
    address usdc = 0xF61Cffd6071a8DB7cD5E8DF1D3A5450D9903cF1c;
    address usdt = 0x0082ef98229887020962624Cbc66092Da5D82AaC;
    address wbtc = 0xde9Fa4A2d8435d45b767506D4A34791fa0371f79;
    address weth = 0x63E537A69b3f5B03F4f46c5765c82861BD874b6e;
    address wmatic = 0x56fC5d9667cb23f045846BE6147a052FdDa26A99;

    address aAave = 0xDf637e801fE9b1fc700d5162A4856b2fb955F3cF;
    address aDai = 0x3D8477D93A0B036Ec3D180fA013848B628c5cb76;
    address aUsdc = 0xc78fd49C2bAd9C8f41ddcE069e34F6a6A627d37f;
    address aUsdt = 0xc5cbFbCE0DDeaF6286d5BCaFe56bd6d6c213b68D;
    address aWbtc = 0x5309E31c80e42FC0cfbf8EbDf7d3D2ABF0df7FE6;
    address aWeth = 0xCa003B920F1CEcb4fe0Fe91B657E58a8E1EED04a;
    address aWmatic = 0xFcA7E60a05c8Baa03189f17Ffa7557FC9FEf68b7;

    address variableDebtDai = 0x8cF5dC18cdA754859b71AC9e96d42CF22f7B42D4;
    address variableDebtUsdc = 0x62fC1B1db6d4ACDcC6720b05AB379165C5121d49;

    address poolAddressesProviderAddress = 0xA5375B08232a0f5e911c8a92B390662e098a579A;
    address aaveIncentivesControllerAddress = address(0);
    // address swapRouterAddress = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    uint24 MORPHO_UNIV3_FEE = 3000;
    uint24 REWARD_UNIV3_FEE = 3000;
}
