/*
  eslint prefer-const: 0,
  max-len: 0,
  object-curly-newline: 1,
  no-param-reassign: 0,
  no-console: 0,
  no-mixed-operators: 0,
  no-floating-decimal: 0,
  no-underscore-dangle:0,
  no-return-assign:0,
*/
const bn = require('bignumber.js')
const { wait } = require('@digix/tempo')(web3)
const {
  gasLogWrapper,
  log,
  timestamp,
  varLogger,
  getParamFromTxEvent,
} = require('./utils')

// I know, it's gross
// add wei converter
/* eslint no-extend-native: 0 */

Number.prototype.toWei = function toWei() {
  return bn(this, 10).times(10 ** 18).toNumber()
}
Number.prototype.toEth = function toEth() {
  return bn(this, 10).div(10 ** 18).toNumber()
}

let genesis_branch = '0xfca5e1a248b8fee34db137da5e38b41f95d11feb5a8fa192a150d8d5d8de1c59'
genesis_branch = new String(genesis_branch).valueOf()
const contractNames = [
  'RealityCheck',
  'RealityToken',
]

/**
 * getContracts - async loads contracts and instances
 *
 * @returns { Mapping(contractName => deployedContract) }
 */
const getContracts = async () => {
  const depContracts = contractNames.map(c => artifacts.require(c)).map(cc => cc.deployed())
  const contractInstances = await Promise.all(depContracts)

  const gasLoggedContracts = gasLogWrapper(contractInstances)

  const deployedContracts = contractNames.reduce((acc, name, i) => {
    acc[name] = gasLoggedContracts[i]
    return acc
  }, {});

  return deployedContracts
}
const initialFunding = 1e10;
const arbitrationCost = 1e19
const feeForRealityToken = 100

/**
 * >setupTest()
 * @param {Array[address]} accounts         => ganache-cli accounts passed in globally
 * @param {Object}         contract         => Contract object obtained via: const contract = await getContracts() (see above)
 * @param {Object}         number Amounts   => { ethAmount = amt to deposit and approve, gnoAmount = for gno, ethUSDPrice = eth price in USD }
 */
const setupTest = async (
  accounts,
  {
    RealityToken: realityToken,
    RealityCheck: realityCheck,
  },
  {
    amountRLT = 50.0.toWei(),
  }) => {


  //distribute funds
  let newFundDistribution = await artifacts.require('./Distribution').new()
  await newFundDistribution.injectReward(accounts, [initialFunding, initialFunding, initialFunding, initialFunding, initialFunding, initialFunding, initialFunding, initialFunding, initialFunding, initialFunding]);
  await newFundDistribution.finalize();
 
  // make accounts[1] as arbitrator
  const ArbitratorData = artifacts.require('./RealityCheckArbitrator'); 
  let arbitratorData = await ArbitratorData.new(realityCheck.address, {from: accounts[1]})
  
  const ArbitratorList = artifacts.require('./ArbitratorList'); 
  let arbitratorList = await ArbitratorList.new([arbitratorData.address]);
  
  // create new branch:
  await wait(86400)

  const transaction = await realityToken.createBranch(genesis_branch, genesis_branch, arbitratorList.address, newFundDistribution.address, 2e20)
  first_branch = getParamFromTxEvent(transaction, 'hash', 'BranchCreated')
  console.log("first branch created with hash"+ first_branch)


  // accounts can claim their rewards
  await newFundDistribution.withdrawReward(realityToken.address, first_branch, {from: accounts[0]})
  await newFundDistribution.withdrawReward(realityToken.address, first_branch, {from: accounts[1]})
  await newFundDistribution.withdrawReward(realityToken.address, first_branch, {from: accounts[2]})
  await newFundDistribution.withdrawReward(realityToken.address, first_branch, {from: accounts[3]})
  await newFundDistribution.withdrawReward(realityToken.address, first_branch, {from: accounts[4]})

  return new String(first_branch).valueOf()
}


module.exports = {
  getContracts,
  setupTest,
  wait,
  bn,
  genesis_branch,
  arbitrationCost,
  initialFunding,
  feeForRealityToken,
}
