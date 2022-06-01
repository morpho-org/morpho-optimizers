import * as dotenv from 'dotenv';
dotenv.config({ path: './.env.local' });
import 'module-alias/register';
import '@openzeppelin/hardhat-upgrades';
import '@tenderly/hardhat-tenderly';
import '@nomiclabs/hardhat-waffle';
import 'hardhat-contract-sizer';
import 'hardhat-gas-reporter';
import 'solidity-coverage';
import 'hardhat-deploy';

module.exports = {
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: {
      accounts: [
        {
          privateKey: process.env.DEPLOYER_PRIVATE_KEY,
          balance: '10000000000000000000000',
        },
      ],
      forking: {
        url: `https://${process.env.NETWORK}.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
      },
      mining: {
        mempool: {
          order: 'fifo',
        },
      },
      gas: 1e7,
    },
    mainnet: {
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      url: `https://mainnet.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
    },
    kovan: {
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      url: `https://kovan.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
    },
    forkMainnet: {
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      url: `https://rpc.tenderly.co/fork/${process.env.TENDERLY_SECRET_KEY}`,
      chainId: 1,
    },
    rinkeby: {
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      url: `https://rinkeby.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
    },
    ropsten: {
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      url: `https://ropsten.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
    },
    polygon: {
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      url: `https://polygon-mainnet.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
      gas: 2100000,
      gasPrice: 8000000000,
    },
    mumbai: {
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      url: `https://polygon-mumbai.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
      gas: 2100000,
      gasPrice: 8000000000,
    },
  },
  namedAccounts: {
    deployer: {
      kovan: '0x2F25DB0982Fd8E8be238281e4b6c413Eda688637',
    },
  },
  solidity: {
    version: '0.8.13',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  gasReporter: {
    currency: 'USD',
  },
  mocha: {
    // needed for the long test of Nmax
    timeout: 300000,
  },
  paths: {
    tests: './test',
  },
};
