import * as dotenv from "dotenv";
import fs from "fs";
import "hardhat-preprocessor";
import { HardhatUserConfig } from "hardhat/config";

import "@nomicfoundation/hardhat-chai-matchers";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "@tenderly/hardhat-tenderly";

// Support for foundry remappings: https://book.getfoundry.sh/config/hardhat
const remappings = fs
  .readFileSync("remappings.txt", "utf8")
  .split("\n")
  .filter(Boolean)
  .map((line) => line.trim().split("="));

dotenv.config({ path: "./.env.local" });

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      forking: {
        url: `https://${process.env.NETWORK || "eth-mainnet"}.g.alchemy.com/v2/${process.env.ALCHEMY_KEY}`,
        blockNumber: Number(process.env.BLOCK_NUMBER || 15_500_000),
      },
    },
    mainnet: {
      url: `https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_KEY}`,
      chainId: 1,
    },
  },
  preprocess: {
    eachLine: () => ({
      transform: (line) => {
        if (line.match(/^\s*import /i)) remappings.forEach(([find, replace]) => (line = line.replace(find, replace)));

        return line;
      },
    }),
  },
  solidity: {
    compilers: [
      {
        version: "0.8.10",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.13",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  paths: {
    sources: "./src",
    tests: "./test-ts",
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

export default config;
