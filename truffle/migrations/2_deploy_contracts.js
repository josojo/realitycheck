var RealityCheck = artifacts.require("./RealityCheck.sol");
var ArbitratorData = artifacts.require("./ArbitratorData.sol");
var ArbitratorList = artifacts.require("./ArbitratorList.sol");
var RealityToken = artifacts.require("./RealityToken.sol");
var InitialDistribution= artifacts.require("./Distribution.sol");

const feeForRealityToken = 100

module.exports = function(deployer, network, accounts) {
    deployer.deploy(RealityToken)
  	.then(()=> deployer.deploy(RealityCheck, RealityToken.address, feeForRealityToken))
}
