// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.0;

import "src/compound/libraries/Types.sol";

contract Config {
    address constant cBat = 0xCCaF265E7492c0d9b7C2f0018bf6382Ba7f0148D;
    address constant cDai = 0x822397d9a55d0fefd20F5c4bCaB33C5F65bd28Eb;
    address constant cEth = 0x20572e4c090f15667cF7378e16FaD2eA0e2f3EfF;
    address constant cRep = 0x1d70B01A2C3e3B2e56FcdcEfe50d5c5d70109a5D;
    address constant cSai = 0x5D4373F8C1AF21C391aD7eC755762D8dD3CCA809;
    address constant cUsdc = 0xCEC4a43eBB02f9B80916F1c718338169d6d5C1F0;
    address constant cWbtc2 = 0x6CE27497A64fFFb5517AA4aeE908b1E7EB63B9fF;
    address constant cZrx = 0xA253295eC2157B8b69C44b2cb35360016DAa25b1;

    address constant wEth = 0xb7e94Cce902E34e618A23Cb82432B95d03096146;
    address constant comptroller = 0x627EA49279FD0dE89186A58b8758aD02B6Be2867;

    uint256 constant defaultMaxSortedUsers = 8;
    Types.MaxGasForMatching defaultMaxGasForMatching =
        Types.MaxGasForMatching({supply: 1e5, borrow: 1e5, withdraw: 1e5, repay: 1e5});
}
