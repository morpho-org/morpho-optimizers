require("dotenv").config({ path: "./.env.local" });
require("@nomiclabs/hardhat-etherscan");
require("@giry/hardhat-test-solidity");
require("@nomiclabs/hardhat-waffle");
require("hardhat-contract-sizer");
require("hardhat-gas-reporter");
require("solidity-coverage");
require("hardhat-deploy");

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      forking: {
        // url: `https://eth-trace.gateway.pokt.network/v1/lb/${process.env.POCKET_NETWORK_ID}`
        url: `https://mainnet.infura.io/v3/${process.env.INFURA_PROJECT_ID}`
      },
      allowUnlimitedContractSize: true,
      blockNumber: 7710600, // Beginning from a specific block number allows caching data and a faster setup.
    },
    kovan: {
      accounts: ["0xae756dcb08a84a119e4910d1ba4dfeb180b0ec5ec4a25223fae2669f36559dd1"],
      // privateKey: "0x574028dad40752ed4448624f35ecb32821b0b0791652a34c10aa78053a08a730",
      url: `https://kovan.infura.io/v3/${process.env.INFURA_PROJECT_ID}`
    },
    rinkeby: {
      accounts: ["0xae756dcb08a84a119e4910d1ba4dfeb180b0ec5ec4a25223fae2669f36559dd1"],
      url: `https://rinkeby.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
      gas: 2100000,
      gasPrice: 8000000000
    },
    ropsten: {
      accounts: ["0xae756dcb08a84a119e4910d1ba4dfeb180b0ec5ec4a25223fae2669f36559dd1"],
      url: `https://ropsten.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
      gas: 2100000,
      gasPrice: 8000000000
    }
  },
  namedAccounts: {
    deployer: {
        "kovan": "0x2F25DB0982Fd8E8be238281e4b6c413Eda688637",
    },
  },
  solidity: {
    version: "0.8.7",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  },
  gasReporter: {
    currency: 'USD',
  },
  mocha: {
    timeout: 50000,
  },
};
