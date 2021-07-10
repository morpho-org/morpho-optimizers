const ChainlinkOracle = artifacts.require('ChainlinkOracle')
const CompoundModule = artifacts.require('CompoundModule')


module.exports = async function(deployer, network, accounts) {

  // Deploy Contracts
  await deployer.deploy(ChainlinkOracle)
  await deployer.deploy(CompoundModule)
}