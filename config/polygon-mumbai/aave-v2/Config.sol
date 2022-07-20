pragma solidity ^0.8.0;

import "@contracts/aave-v2/libraries/Types.sol";

contract Config {
    address constant lendingPool = 0x9198F13B08E299d85E096929fA9781A1E3d5d827;
    address constant lendingPoolAddressesProvider = 0x178113104fEcbcD7fF8669a0150721e231F0FD4B;

    address constant aave = 0x341d1f30e77D3FBfbD43D17183E2acb9dF25574E;
    address constant dai = 0x001B3B4d0F3714Ca98ba10F6042DaEbF0B1B7b6F;
    address constant usdc = 0x2058A9D7613eEE744279e3856Ef0eAda5FCbaA7e;
    address constant usdt = 0xBD21A10F619BE90d6066c941b04e340841F1F989;
    address constant wbtc = 0x0d787a4a1548f673ed375445535a6c7A1EE56180;
    address constant weth = 0x3C68CE8504087f89c640D02d133646d98e64ddd9;
    address constant wmatic = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;

    uint256 constant defaultMaxSortedUsers = 8;
    Types.MaxGasForMatching defaultMaxGasForMatching =
        Types.MaxGasForMatching({supply: 1e5, borrow: 1e5, withdraw: 1e5, repay: 1e5});
}
