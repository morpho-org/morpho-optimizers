import * as dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/config";

import "@nomicfoundation/hardhat-chai-matchers";
import "@nomiclabs/hardhat-ethers";

dotenv.config({ path: "./.env.local" });

const config: HardhatUserConfig = {
  solidity: "0.8.13",
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      forking: {
        enabled: true,
        url: `https://${process.env.NETWORK}.g.alchemy.com/v2/${process.env.ALCHEMY_KEY}`,
        blockNumber: Number(process.env.BLOCK_NUMBER ?? 15_580_517),
      },
    },
  },
  paths: {
    sources: "./test/contracts/",
  },
};

export default config;
