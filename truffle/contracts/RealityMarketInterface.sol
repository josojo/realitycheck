pragma solidity ^0.4.18;


contract RealityMarketInterface{
	    address masterCopy;
	    bytes32 public parentReality;
	    bytes32 public childReality;
	    address realityToken;
	    mapping (address => uint) buyOrders;
	    mapping (address => uint) sellOrders;

	    uint public totalSellVolume;
	    uint public totalBuyVolume;
	    uint public marketStartTime;
	    uint public currentPeriod;
	    uint public lastTotalSellVolume;
	    uint constant ONETRADEPERIOD=60*60*24;

	    mapping (address => bytes32[]) withdrawBranchesForChildTokens;
	    mapping (address => bytes32[]) withdrawBranchesForParentTokens;
	function initializeAuction(uint amount, bytes32 childReality_, bytes32 parentReality_, address realityToken_, address sender) public;
}