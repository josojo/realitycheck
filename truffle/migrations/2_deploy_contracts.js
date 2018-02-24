var RealityCheck = artifacts.require("./RealityCheck.sol");
var Arbitrator = artifacts.require("./Arbitrator.sol");
var RealityToken = artifacts.require("./RealityToken.sol");
var DataContract= artifacts.require("./DataContract.sol");
var InitialDistribution= artifacts.require("./Distribution.sol");

const feeForRealityToken = 1000000000000000000
module.exports = function(deployer, network, accounts) {
let DC, ID

let rewards = Array(10).fill(web3.toBigNumber(10e23).valueOf())
  deployer.deploy(InitialDistribution)
  	.then(()=>InitialDistribution.deployed())
  	.then((r)=>{ID=r
  				ID.injectReward(accounts, rewards)})
  	.then(()=>ID.finalize())
  	
  	//Preparing DataContract with intial parameter setup
  	.then(()=>  deployer.deploy(DataContract))
  	.then(()=> DataContract.deployed())
  	.then((D)=> D.setArbitrationCost(100e18))
  	.then(()=> DataContract.deployed()) 
  	.then((D)=> D.finalize())

  	//Deploying RealityToken
  	.then(()=> deployer.deploy(RealityToken, InitialDistribution.address, DataContract.address))
  	.then(()=> RealityToken.deployed())
  	.then((R)=> deployer.deploy(RealityCheck, R.address, feeForRealityToken))
}
