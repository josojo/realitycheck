/* eslint no-console:0, max-len:0, no-plusplus:0, no-mixed-operators:0, no-trailing-spaces:0 */


//
// All tradeflows are desribed in the excel file: 
// https://docs.google.com/spreadsheets/d/1H-NXEvuxGKFW8azXtyQC26WQQuI5jmSxR7zK9tHDqSs/edit#gid=394399433
// They are intended as system tests for running through different auction with different patterns
//  


const { 
  eventWatcher,
  logger,
  timestamp,
  gasLogger,
  enableContractFlag,
  getParamFromTxEvent,
} = require('./utils')

const {
  setupTest,
  getContracts,
  genesis_branch,
  first_branch,
  wait,
  bn,
  arbitrationCost,
  initialFunding,
  feeForRealityToken,
} = require('./testingFunctions')

// Test VARS
let initialDistribution
let dataContract1
let realityToken
let realityCheck
let contracts
let branches 
let questionId
let YES = '0x0000000000000000000000000000000000000000000000000000000000000001'
YES = new String(YES).valueOf()
let NO = '0x0000000000000000000000000000000000000000000000000000000000000000'
NO = new String(NO).valueOf()

const historyHashes = []
const answers = []
const submiters = []
const bonds = []

const setupContracts = async () => {
  contracts = await getContracts();
  // destructure contracts into upper state
  ({
    RealityToken: realityToken,
    RealityCheck: realityCheck,
  } = contracts)
}

const startBal = {
  amountRLT: 50e18,
}
const betAmount = 1e5

const c1 = () => contract('RealityCheck - Escalation with RealityToken as Arbitrator', (accounts) => {
  const [master, arbitrator, RCasker, bonderYES, bonderNO, BranchProvider] = accounts

  before(async () => {
    // get contracts
    await setupContracts()
    // set up accounts and tokens[contracts]
    const first_branch = await setupTest(accounts, contracts, startBal)
    branches = [[genesis_branch], [first_branch]]
  })

  afterEach(gasLogger)

  it('step 1 - RCasker is asking a question and handing out a bounty', async () => {
    await realityToken.approve(realityCheck.address, betAmount, branches[1][0], { from: RCasker })
    assert.equal((await realityToken.allowance(RCasker, realityCheck.address, branches[1][0])).toNumber(), betAmount)
    const transaction = await realityCheck.askQuestion(0, 'is BTC the true Bitcoin', 60 * 60 * 10, 0, 0, betAmount, branches[1][0], 0, { from: RCasker })
    questionId = getParamFromTxEvent(transaction, 'question_id', 'LogNewQuestion')
    console.log(`question asked with question_id${questionId}`)
  })

  it('step 2 - bonderYES provides the answer Yes', async () => {
    await realityToken.approve(realityCheck.address, betAmount, branches[1][0], { from: bonderYES })
    assert.equal((await realityToken.allowance(bonderYES, realityCheck.address, branches[1][0])).toNumber(), betAmount)
    const transaction = await realityCheck.submitAnswer(questionId, YES, betAmount, betAmount, { from: bonderYES })
    historyHashes.push(new String(getParamFromTxEvent(transaction, 'history_hash', 'LogNewAnswer')).valueOf())
    answers.push(YES)
    submiters.push(bonderYES)
    bonds.push(betAmount)
  })

  it('step 3 - bonderNo provides the answer No doubling the bonding', async () => {
    await realityToken.approve(realityCheck.address, 2 * betAmount, branches[1][0], { from: bonderNO })
    assert.equal((await realityToken.allowance(bonderNO, realityCheck.address, branches[1][0])).toNumber(), 2 * betAmount)
    const transaction = await realityCheck.submitAnswer(questionId, NO, 2 * betAmount, 2 * betAmount, { from: bonderNO })
    historyHashes.push(new String(getParamFromTxEvent(transaction, 'history_hash', 'LogNewAnswer')).valueOf())
    answers.push(NO)
    submiters.push(bonderNO)
    bonds.push(2 * betAmount)
  })
  it('step 5 - bonderYes pays the RealityToken to arbitrate', async () => {
    const arbitratorList = artifacts.require('./ArbitratorList').at(await realityToken.getArbitratorList(branches[1][0]))
    const arbitratorData = artifacts.require('./RealityCheckArbitrator').at(await arbitratorList.arbitrators(0))
    await arbitratorData.notifyOfArbitrationRequest(questionId, bonderNO, branches[1][0], { from: arbitrator })
  })
  it('step 6 - Arbitrator submits the answer Yes and new branch is submitted', async () => {
    const arbitratorList = artifacts.require('./ArbitratorList').at(await realityToken.getArbitratorList(branches[1][0]))
    // create new branch:
    await wait(86400)

    const transaction = await realityToken.createBranch(branches[1][0], genesis_branch, arbitratorList.address, master, 0)
    const second_branch = getParamFromTxEvent(transaction, 'hash', 'BranchCreated')
    console.log(`second branch created with hash${second_branch}`)
    branches.push([second_branch])

    const arbitratorData = artifacts.require('./RealityCheckArbitrator').at(await arbitratorList.arbitrators(0))
    await arbitratorData.addAnswer([questionId], [YES], [7], { from: arbitrator })

    // create new branch:
    await wait(86400)
    const transaction2 = await realityToken.createBranch(branches[2][0], genesis_branch, arbitratorList.address, master, 0)
    const third_branch = getParamFromTxEvent(transaction2, 'hash', 'BranchCreated')
    console.log(`second branch created with hash${third_branch}`)
    branches.push([third_branch])

  })
  it('step 7 - BonderNO makes himself a arbitrator, and submits the answer No in a new branch', async () => {
    const arbitratorData = await artifacts.require('./RealityCheckArbitrator').new(realityCheck.address, { from: bonderNO })
    const arbitratorList = await artifacts.require('./ArbitratorList').new([arbitratorData.address])
    
    await arbitratorData.addAnswer([questionId], [NO], [7], { from: bonderNO })

    const transaction = await realityToken.createBranch(branches[1][0], genesis_branch, arbitratorList.address, master, 0)
    const second_branch = getParamFromTxEvent(transaction, 'hash', 'BranchCreated')
    console.log(`second branch created with hash${second_branch}`)
    branches[2][1] = second_branch
  })
  it('step 8 - BonderYes withdraws the winnings on the yes branch', async () => {
    submiters.reverse()
    bonds.reverse()
    answers.reverse()

    await realityCheck.claimWinnings(
      branches[3][0],
      NO,
      questionId, 
      [historyHashes[0], NO],
      submiters,
      bonds,
      answers,
    )
    assert.equal((await realityToken.balanceOf(bonderYES, branches[3][0])).toNumber(), initialFunding + betAmount + 2 * betAmount - feeForRealityToken)
    assert.equal((await realityToken.balanceOf(bonderNO, branches[3][0])).toNumber(), initialFunding - 2 * betAmount )
  })
  it('step 9 - BonderNo withdraws the winnings on the no branch', async () => {
    const previousBal = (await realityToken.balanceOf(bonderNO, branches[2][1]))
    await realityCheck.claimWinnings(
      branches[2][1],
      NO,
      questionId, 
      [historyHashes[0], NO],
      submiters,
      bonds,
      answers,
    ) 
    assert.equal((await realityToken.balanceOf(bonderNO, branches[2][1])).toNumber(), initialFunding + betAmount + betAmount - feeForRealityToken)
    assert.equal((await realityToken.balanceOf(bonderYES, branches[2][1])).toNumber(), initialFunding - betAmount)
  
  })
})

enableContractFlag(c1)
