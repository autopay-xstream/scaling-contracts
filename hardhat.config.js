require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();
require("@nomiclabs/hardhat-etherscan");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    hardhat: {
      forking: {
        url: process.env.ALCHEMY_MUMBAI_API_URL ,
        blockNumber: 27143614
      }
    },
    goerli: {
      url: process.env.ALCHEMY_GOERLI_API_URL,
      accounts: [process.env.PRIVATE_KEY]
    },
    mumbai: {
      url: process.env.ALCHEMY_MUMBAI_API_URL,
      accounts: [process.env.PRIVATE_KEY],
      gasPrice: 1000000000000
    },
    gnosis: {
      url: process.env.ALCHEMY_GNOSIS_API_URL,
      accounts: [process.env.PRIVATE_KEY2]
    },
    polygon: {
      url: process.env.ALCHEMY_POLYGON_API_URL,
      accounts: [process.env.PRIVATE_KEY]
    },
  },
  etherscan: {
    apiKey: process.env.POLYGONSCAN_API_KEY
  },
  polygonscan: {
    apiKey: process.env.POLYGONSCAN_API_KEY
  }
};
