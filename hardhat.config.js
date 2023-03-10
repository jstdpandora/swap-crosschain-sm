require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();
require("hardhat-gas-reporter");

module.exports = {
  gasReporter: {
    enabled: process.env.REPORT_GAS ? true : false,
    currency: "USD",
    coinmarketcap: process.env.REPORT_GAS.COIN_MKC_API_KEY,
    token: "ETH",
  },
  solidity: {
    version: "0.8.17",
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 300,
      },
    },
  },
  mocha: {
    timeout: 100000000,
  },
  networks: {
    hardhat: {
      forking: {
        url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
      },
    },
  },
};
