// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

contract Config {
    address aave = 0xde9Fa4A2d8435d45b767506D4A34791fa0371f79;
    address dai = 0x63E537A69b3f5B03F4f46c5765c82861BD874b6e;
    address usdc = 0x02444D214962eC73ab733bB00Ca98879efAAa73d;
    address usdt = 0x18eE6714Bb1796b8172951D892Fb9f42a961C812;
    address wbtc = 0xE341D799E61d9caDBB6b05539f1d10aAdfA24d70;
    address weth = 0xB7348Df015BB2e67449406FD1283DbAc99Ab716B;
    address wavax = 0x37FAb20e8E95Abe04f7B7eA0BF9774654E3D17a7;

    address aAave = 0xDd2CD768a666f4D695B53edCb1034B3Fc8404C23;
    address aDai = 0x51a027ccDC1ED066A37BBC450cc168A8649a3Ce1;
    address aUsdc = 0x416dE1aB5e9AbDd08bdc4837dFe930dC133E210E;
    address aUsdt = 0xDC48792e03cA45168EA94892DeB747c459aa71EC;
    address aWbtc = 0x461a7c5E48ee173132C45690b1F5A3e85F274FA9;
    address aWeth = 0x251B4dDFf00a08E3C341D7f781e1856C3C3e44fb;
    address avWavax = 0xd3da42e85Ebe7bE9cF01Ae054A2046474c448a0f;

    address variableDebtDai = 0xBe37D89d44755E787203E11F22c2eE3E1E36394d;
    address variableDebtUsdc = 0x89Dfd248acfEeFE5af4E3BB65E20B187C5FCeBfF;

    address poolAddressesProviderAddress = 0xd5B55D3Ed89FDa19124ceB5baB620328287b915d;
    address aaveIncentivesControllerAddress = address(0);
    // address swapRouterAddress = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4;

    uint24 MORPHO_UNIV3_FEE = 3000;
    uint24 REWARD_UNIV3_FEE = 3000;
}
