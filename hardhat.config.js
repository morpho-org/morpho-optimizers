/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require('dotenv').config({ path: './.env.local' });
require("@nomiclabs/hardhat-waffle");
require("solidity-coverage");

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      forking: {
        url: `https://eth-trace.gateway.pokt.network/v1/lb/${process.env.POCKET_NETWORK_ID}`
        // url: `https://mainnet.infura.io/v3/${process.env.INFURA_PROJECT_ID}`
      },
      // accounts: [
      //   {
      //     privateKey: "0xae756dcb08a84a119e4910d1ba4dfeb180b0ec5ec4a25223fae2669f36559dd1", // Lender
      //     balance: "10000000000000000000000"
      //   },
      //   {
      //     privateKey: "0x574028dad40752ed4448624f35ecb32821b0b0791652a34c10aa78053a08a730", // Borrower
      //     balance: "10000000000000000000000"
      //   },
      // ],
      blockNumber: 7710600 // Beginning from a specific block number allows caching data and a faster setup.
    }
  },
  solidity: {
    version: "0.8.6",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  mocha: {
    timeout: 50000
  }
};
