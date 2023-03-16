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
  etherscan: {
    apiKey: "PP1ZDPFX8RCDDDY6RBK15I1EDQM4SKJZ3N",
  },
  networks: {
    sepolia: {
      url: `https://eth-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_SEPOLIA_KEY}`,
      accounts: [process.env.PRIVATE_KEY],
    },
  },
};
