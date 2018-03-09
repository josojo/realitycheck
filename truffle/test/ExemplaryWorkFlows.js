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
    DataContract: dataContract1,
    Distribution: initialDistribution,
  } = contracts)
}

const startBal = {
  amountRLT: 50e18,
}


const c1 = () => contract('RealityCheck - Escalation with RealityToken as Arbitrator', (accounts) => {
  const [master, RCasker, bonderYES, bonderNO, BranchProvider] = accounts

  before(async () => {
    // get contracts
    await setupContracts()
    // set up accounts and tokens[contracts]
    const first_branch = await setupTest(accounts, contracts, startBal)
    branches = [[genesis_branch], [first_branch]]
  })

  afterEach(gasLogger)

  it('step 1 - RCasker is asking a question and handing out a bounty', async () => {
    await realityToken.approve(realityCheck.address, 2e18, branches[1][0], { from: RCasker })
    assert.equal((await realityToken.allowance(RCasker, realityCheck.address, branches[1][0])).toNumber(), 2e18)
    const transaction = await realityCheck.askQuestion(0, 'is BTC the true Bitcoin', 60 * 60 * 10, 0, 0, 2e18, branches[1][0], { from: RCasker })
    questionId = getParamFromTxEvent(transaction, 'question_id', 'LogNewQuestion')
    console.log(`question asked with question_id${questionId}`)
  })

  it('step 2 - bonderYES provides the answer Yes', async () => {
    await realityToken.approve(realityCheck.address, 2e18, branches[1][0], { from: bonderYES })
    assert.equal((await realityToken.allowance(bonderYES, realityCheck.address, branches[1][0])).toNumber(), 2e18)
    const transaction = await realityCheck.submitAnswer(questionId, YES, 2e18, 2e18, { from: bonderYES })
    historyHashes.push(new String(getParamFromTxEvent(transaction, 'history_hash', 'LogNewAnswer')).valueOf())
    answers.push(YES)
    submiters.push(bonderYES)
    bonds.push(2e18)
  })

  it('step 3 - bonderNo provides the answer No doubling the bonding', async () => {
    await realityToken.approve(realityCheck.address, 4e18, branches[1][0], { from: bonderNO })
    assert.equal((await realityToken.allowance(bonderNO, realityCheck.address, branches[1][0])).toNumber(), 4e18)
    const transaction = await realityCheck.submitAnswer(questionId, NO, 4e18, 4e18, { from: bonderNO })
    historyHashes.push(new String(getParamFromTxEvent(transaction, 'history_hash', 'LogNewAnswer')).valueOf())
    answers.push(NO)
    submiters.push(bonderNO)
    bonds.push(4e18)
  })
  it('step 5 - bonderYes pays the RealityToken to arbitrate', async () => {
    await realityToken.approve(realityCheck.address, arbitrationCost, branches[1][0], { from: bonderNO })
    await realityCheck.notifyOfArbitrationRequest(questionId, { from: bonderNO })
  })
  it('step 6 - BranchProvider submits the answer Yes in a new branch', async () => {
    newDataContract = await artifacts.require('./DataContract').new({ from: BranchProvider })
    await newDataContract.addAnswer([questionId], [YES], { from: BranchProvider })
    await newDataContract.finalize({ from: BranchProvider })
    await wait(86400)
    const transaction = await realityToken.createBranch(branches[1][0], genesis_branch, newDataContract.address, 1, 0, 0, { from: BranchProvider })
    const second_branch = getParamFromTxEvent(transaction, 'hash', 'BranchCreated')
    branches.push([second_branch])
  })
  it('step 7 - BonderNO submits the answer No in a new branch', async () => {
    newDataContract = await artifacts.require('./DataContract').new({ from: bonderNO })
    await newDataContract.addAnswer([questionId], [NO], { from: bonderNO })
    await newDataContract.finalize({ from: bonderNO })
    const transaction = await realityToken.createBranch(branches[1][0], genesis_branch, newDataContract.address, 1, 0, 0, { from: bonderNO })
    const second_branch = getParamFromTxEvent(transaction, 'hash', 'BranchCreated')
    branches[2][1] = second_branch
  })
  it('step 8 - BonderYes withdraws the winnings on the yes branch', async () => {
    submiters.reverse()
    bonds.reverse()
    answers.reverse()

    await realityCheck.claimWinnings(
      branches[2][0],
      NO,
      questionId, 
      [historyHashes[0], NO],
      submiters,
      bonds,
      answers,
    ) 
    assert.equal((await realityToken.balanceOf(bonderYES, branches[2][0])).toNumber(), 10e23 + 5e18)
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
    const newBalance = (await realityToken.balanceOf(bonderNO, branches[2][1]))
    assert.equal((newBalance.sub(previousBal)).toNumber(), 7e18)
  })
})

enableContractFlag(c1)
