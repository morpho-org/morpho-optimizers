// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/compound/libraries/Types.sol";

contract Config {
    address constant wEth = address(0);
    address constant dai = 0x31F42841c2db5173425b5223809CF3A38FEde360;
    address constant usdc = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F;
    address constant usdt = 0x110a13FC3efE6A245B50102D2d79B3E76125Ae83;
    address constant wbtc = 0x442Be68395613bDCD19778e761f03261ec46C06D;
    address constant bat = 0x50390975D942E83D661D4Bde43BF73B0ef27b426;
    address constant uni = 0xC8F88977E21630Cf93c02D02d9E8812ff0DFC37a;
    address constant comp = 0xf76D4a441E4ba86A923ce32B89AFF89dBccAA075;
    address constant zrx = 0xc0e2D7d9279846B80EacdEa57220AB2333BC049d;
    address constant rep = 0xb1cBa8b721C7a241b9AD08C17F328886B014ACfE;
    address constant sai = 0x63F7AB2f24322Ae2eaD6b971Cb9a71A1CC2eee03;

    address constant cEth = 0x859e9d8a4edadfEDb5A2fF311243af80F85A91b8;
    address constant cDai = 0xbc689667C13FB2a04f09272753760E38a95B998C;
    address constant cUsdc = 0x2973e69b20563bcc66dC63Bde153072c33eF37fe;
    address constant cUsdt = 0xF6958Cf3127e62d3EB26c79F4f45d3F3b2CcdeD4;
    address constant cWbtc2 = 0x541c9cB0E97b77F142684cc33E8AC9aC17B1990F;
    address constant cBat = 0xaF50a5A6Af87418DAC1F28F9797CeB3bfB62750A;
    address constant cUni = 0x65280b21167BBD059221488B7cBE759F9fB18bB5;
    address constant cComp = 0x70014768996439F71C041179Ffddce973a83EEf2;
    address constant cZrx = 0x6B8b0D7875B4182Fb126877023fB93b934dD302A;
    address constant cRep = 0x2862065D57749f1576F48eF4393eb81c45fC2d88;
    address constant cSai = 0x7Ac65E0f6dBA0EcB8845f17d07bF0776842690f8;

    address constant comptroller = 0xcfa7b0e37f5AC60f3ae25226F5e39ec59AD26152;

    uint256 constant defaultMaxSortedUsers = 8;
    Types.MaxGasForMatching defaultMaxGasForMatching =
        Types.MaxGasForMatching({supply: 1e5, borrow: 1e5, withdraw: 1e5, repay: 1e5});
}
