const CompoundModule = artifacts.require('CompoundModule')


module.exports = async function(deployer, network, accounts) {

  // Deploy Contracts
  await deployer.deploy(CompoundModule)
}