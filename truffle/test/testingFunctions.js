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
  'DataContract',
  'RealityCheck',
  'RealityToken',
  'Distribution',
]
// DutchExchange and TokenOWL are added after their respective Proxy contracts are deployed

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

const arbitrationCost = 1e19

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
    DataContract: dataContract,
    Distribution: distribution,
  },
  {
    amountRLT = 50.0.toWei(),
  }) => {
  //distribute funds
  await Promise.all(accounts.map((acct) => {
    distribution.withdrawReward(realityToken.address, genesis_branch, { from: acct})
  }))
  assert.equal((await realityToken.balanceOf(accounts[0],genesis_branch)).toNumber(),10e23)
  console.log('tokendistribtuion done')

  // asking a first question
  newDataContract = await artifacts.require('./DataContract').new({from: accounts[0]})
  //await newDataContract.SupportDapp([realityCheck.address])
  await newDataContract.setArbitrationCost(arbitrationCost)
  await newDataContract.finalize()
  await wait(86400)
  const transaction = await realityToken.createBranch(genesis_branch, genesis_branch, newDataContract.address)
  first_branch = getParamFromTxEvent(transaction, 'hash', 'BranchCreated')
  return new String(first_branch).valueOf()
}


module.exports = {
  getContracts,
  setupTest,
  wait,
  bn,
  genesis_branch,
  arbitrationCost,
}
