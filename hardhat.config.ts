import "@nomicfoundation/hardhat-toolbox";
import "hardhat-etherscan-abi";
import * as dotenv from 'dotenv';
dotenv.config()

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.17",
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      forking: {
        url: `https://eth-mainnet.g.alchemy.com/v2/${process.env.MAINNET_ALCHEMY_KEY}`,
        blockNumber: 15476666
      }
    },
  },
  etherscan: {
    apiKey: process.env.MAINNET_ETHERSCAN_KEY
  },
  settings: {
    optimizer: {
      enabled: true,
      runs: 500
    }
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 200000
  },
  typechain: {
    target: 'ethers-v5',
    alwaysGenerateOverloads: false,
  }
};