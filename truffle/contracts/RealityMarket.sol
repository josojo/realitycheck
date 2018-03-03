pragma solidity ^0.4.18;

import './SafeMath.sol';
import './SafeMath32.sol';
import './RealityToken.sol';


contract RealityMarket{
	    address masterCopy;
	    bytes32 public parentReality;
	    bytes32 public childReality;
	    RealityToken realityToken;
	    mapping (address => uint) buyOrders;
	    mapping (address => uint) sellOrders;
	    uint public timeOfCreation;
	    uint public totalSellVolume;
	    uint public totalBuyVolume;
	    uint public marketStartTime;
	    uint public currentPeriod;
	    uint public lastTotalSellVolume;
	    uint constant ONETRADEPERIOD=60*60*24;

	    mapping (address => bytes32[]) withdrawBranchesForChildTokens;
	    mapping (address => bytes32[]) withdrawBranchesForParentTokens;

	function initializeAuction(uint amount, bytes32 childReality_, bytes32 parentReality_, address realityToken_, address sender)
	public 
	{
		require(realityToken==address(0));
		require(realityToken.transferFrom(sender,this, amount, parentReality));
		//setting initial variables
		realityToken = RealityToken(realityToken_);
		parentReality = parentReality_;
		childReality = childReality_;
		timeOfCreation = now;
		// process the first buyParentOrder
		buyOrders[sender]+= amount;
		totalBuyVolume+=amount;
	}

	function sellParentTokens(uint amount)
	public{
		require(currentPeriod<=6);
		amount = max(amount, totalBuyVolume - totalSellVolume);
		require(realityToken.transferFrom(msg.sender,this, amount, parentReality));	
		sellOrders[msg.sender]+= amount;
		totalSellVolume+=amount;
	}

	function buyParentTokens(uint amount)
	public{
		uint FACTOR=0;
		if(now>ONETRADEPERIOD*(currentPeriod+1)){
			currentPeriod=uint((now-timeOfCreation)/ONETRADEPERIOD);
			lastTotalSellVolume=totalSellVolume;
		}
		if(currentPeriod>0){
			FACTOR=200;	
		}
		if(currentPeriod>1){
			FACTOR=150;	
		}
		if(currentPeriod>2){
			FACTOR=125;	
		}
		if(currentPeriod>3){
			FACTOR=112;	
		}
		if(currentPeriod>4){
			FACTOR=105;	
		}
		if(currentPeriod>5){
			FACTOR=102;	
		}
		require(currentPeriod<=6);
		amount = max(amount, lastTotalSellVolume*FACTOR/100 - totalSellVolume);
		require(realityToken.transferFrom(msg.sender,this, amount, childReality));	
		buyOrders[msg.sender]+= amount;
		totalBuyVolume+=amount;
	}

	//withdraw is only possible on parentbranch
	function withdrawParentTokens(bytes32 branchForWithdraw, bool  gasEfficient) public {
		require((now-timeOfCreation)/ONETRADEPERIOD>6);

		for(uint i=0;i<withdrawBranchesForParentTokens[msg.sender].length;i++){
			require(!realityToken.isBranchInBetweenBranches(withdrawBranchesForParentTokens[msg.sender][i], childReality,branchForWithdraw));
		}

		uint amount = buyOrders[msg.sender]*totalSellVolume/totalBuyVolume;
		realityToken.transfer(msg.sender, amount, parentReality);
		if(gasEfficient){
			buyOrders[msg.sender]=0;
		} else {
			withdrawBranchesForParentTokens[msg.sender].push(branchForWithdraw);
		}
	}

	//withdraws is only possible on direct parentbranches of child branch
	function withdrawChildTokens(bytes32 branchForWithdraw, bool gasEfficient) public {
		require((now-timeOfCreation)/ONETRADEPERIOD>6);
		for(uint i=0;i<withdrawBranchesForChildTokens[msg.sender].length;i++){
			require(!realityToken.isBranchInBetweenBranches(withdrawBranchesForChildTokens[msg.sender][i], childReality,branchForWithdraw));
		}
			uint amount = sellOrders[msg.sender]*totalBuyVolume/totalSellVolume;
			realityToken.transfer(msg.sender, amount, branchForWithdraw);

		if(gasEfficient)
			sellOrders[msg.sender]=0;
		else{
			withdrawBranchesForChildTokens[msg.sender].push(branchForWithdraw);
		}	
	}
	function max(uint a, uint b)
	public returns(uint){
		if(a>b)
		return a;
		else return b;
	}
}