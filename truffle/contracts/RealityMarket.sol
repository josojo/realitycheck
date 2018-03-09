pragma solidity ^0.4.18;

import './SafeMath.sol';
import './SafeMath32.sol';
import './RealityToken.sol';


contract RealityMarket{
		// masterCopy needs to be specified to make the ProxyContract work.
	    address masterCopy;

	    bytes32 public parentReality;
	    bytes32 public childReality;
	    RealityToken realityToken;
   	    uint public timeOfCreation;
   	    //tracking orders from users
	    mapping (address => uint) buyChildOrders;
	    mapping (address => uint) buyParentOrders;
	    //tracking total sum of orders 
	    uint public totalBuyChildTokenVolume;
	    uint public totalBuyParentTokenVolume;
	    
	    uint public currentPeriodBuyParent;
	    uint public currentPeriodBuyChild;

	    uint public lastTotalBuyParentTokenVolume;

	    uint public prevUpperLimitForPriceNum=1;
	    uint public prevUpperLimitForPriceDen=1;
	    uint public prevPrevUpperLimitForPriceNum=1;
	    uint public prevPrevUpperLimitForPriceDen=1;
	    uint public upperLimitForPriceNum=1;
	    uint public upperLimitForPriceDen=1;
	    
	    uint constant ONE_TRADE_PERIOD=(1 days);

	    mapping (address => bytes32[]) withdrawBranchesForChildTokens;
	    mapping (address => bytes32[]) withdrawBranchesForParentTokens;


    modifier auctionEnded() {
        require(isAuctionClosed());
        _;
    }
    //@dev initializes the auction and processes the first buyParentTokens from the branch creator
	function initializeAuction(uint amount, bytes32 childReality_, bytes32 parentReality_, address realityToken_, address sender)
	public 
	{
		require(realityToken_ != address(0));
		require(RealityToken(realityToken_).transferFrom(sender,this, amount, parentReality_));
		//setting initial variables
		realityToken = RealityToken(realityToken_);
		parentReality = parentReality_;
		childReality = childReality_;
		timeOfCreation = now;
		// process the first buyParentOrder
		buyChildOrders[sender] += amount;
		totalBuyChildTokenVolume += amount;
	}
    //@dev allows to participate in the auction and sell child RealityTokens against Parent RealityTokens
    //@dev the maximal amount of tokens to be sold is limited after the first TRADE_PERIOD and for all subsequent 
    //@dev auctions less and less tokens are allowed to sell. This mechaism helps to migrate huge price changes
    //@dev in the last minutes of an auction
    //@param amount amount of child RealityTokens submitted into the auction
	function buyParentTokens(uint amount)
	public{
		uint FACTOR=0;
		if(now>ONE_TRADE_PERIOD*(currentPeriodBuyParent+1)){
			currentPeriodBuyParent=uint((now-timeOfCreation)/ONE_TRADE_PERIOD);
			lastTotalBuyParentTokenVolume=totalBuyParentTokenVolume;
		}
		if(currentPeriodBuyParent==1){
			FACTOR=400;	
		}
		if(currentPeriodBuyParent==2){
			FACTOR=200;	
		}
		if(currentPeriodBuyParent==3){
			FACTOR=100;	
		}
		if(currentPeriodBuyParent==4){
			FACTOR=50;	
		}
		if(currentPeriodBuyParent==5){
			FACTOR=25;	
		}
		if(currentPeriodBuyParent==6){
			FACTOR=5;	
		}
		require(currentPeriodBuyParent<=6);
		amount = max(amount, lastTotalBuyParentTokenVolume*FACTOR/100 - totalBuyParentTokenVolume);
		require(realityToken.transferFrom(msg.sender,this, amount, childReality));	
		buyParentOrders[msg.sender]+= amount;
		totalBuyParentTokenVolume+=amount;
	}
	//@dev allows to participate in the auction and sell parent RealityTokens against child RealityTokens
    //@dev the maximal amount of tokens to be sold will be limited in a Trading period so that a price child / parent RealityTokens
    //@dev can not be pushed higher than certain prices seen earlier in the market
    //@param amount amount of parent RealityTokens submitted into the auction
	function buyChildTokens(uint amount)
	public{
		if(now>ONE_TRADE_PERIOD*(currentPeriodBuyChild+1)){
			uint tempCurrentPeriodBuyChild = uint((now-timeOfCreation)/ONE_TRADE_PERIOD);
			if(tempCurrentPeriodBuyChild>currentPeriodBuyChild + 1)
			{
				if(totalBuyChildTokenVolume*prevPrevUpperLimitForPriceDen <= totalBuyParentTokenVolume*prevUpperLimitForPriceDen){
						upperLimitForPriceNum = prevPrevUpperLimitForPriceNum;
						upperLimitForPriceDen = prevPrevUpperLimitForPriceDen;
				}
				prevPrevUpperLimitForPriceNum = prevUpperLimitForPriceNum;
				prevPrevUpperLimitForPriceDen = prevUpperLimitForPriceDen;
				prevUpperLimitForPriceNum = totalBuyChildTokenVolume;
				prevUpperLimitForPriceDen = totalBuyParentTokenVolume;	
			}else{
				if(prevUpperLimitForPriceNum*prevPrevUpperLimitForPriceDen <= prevUpperLimitForPriceDen*prevUpperLimitForPriceDen)
					if(totalBuyChildTokenVolume*prevPrevUpperLimitForPriceDen <= totalBuyParentTokenVolume*prevUpperLimitForPriceDen){
						upperLimitForPriceNum = prevPrevUpperLimitForPriceNum;
						upperLimitForPriceDen = prevPrevUpperLimitForPriceDen;
					}
				prevPrevUpperLimitForPriceNum = prevUpperLimitForPriceNum;
				prevPrevUpperLimitForPriceDen = prevUpperLimitForPriceDen;
				prevUpperLimitForPriceNum = totalBuyChildTokenVolume;
				prevUpperLimitForPriceDen = totalBuyParentTokenVolume;	
			}
			currentPeriodBuyChild=uint((now-timeOfCreation)/ONE_TRADE_PERIOD);
		}
		amount = max(amount, upperLimitForPriceNum*totalBuyParentTokenVolume/upperLimitForPriceDen - totalBuyChildTokenVolume);
		require(realityToken.transferFrom(msg.sender,this, amount, parentReality));	
		buyChildOrders[msg.sender]+= amount;
		totalBuyChildTokenVolume+=amount;
	}

	//withdraw is only possible on parentbranch
	function withdrawParentTokens(bytes32 branchForWithdraw, bool  gasEfficient) 
		auctionEnded()
	public {
		for(uint i=0;i<withdrawBranchesForParentTokens[msg.sender].length;i++){
			require(!realityToken.isBranchInBetweenBranches(withdrawBranchesForParentTokens[msg.sender][i], childReality,branchForWithdraw));
		}

		uint amount = buyParentOrders[msg.sender]*totalBuyChildTokenVolume/totalBuyParentTokenVolume;
		realityToken.transfer(msg.sender, amount, parentReality);
		if(gasEfficient){
			buyParentOrders[msg.sender]=0;
		} else {
			withdrawBranchesForParentTokens[msg.sender].push(branchForWithdraw);
		}
	}

	//withdraws is only possible on direct parentbranches of child branch
	function withdrawChildTokens(bytes32 branchForWithdraw, bool gasEfficient) 
		auctionEnded()
	public {
		require((now-timeOfCreation)/ONE_TRADE_PERIOD>6);
		for(uint i=0;i<withdrawBranchesForChildTokens[msg.sender].length;i++){
			require(!realityToken.isBranchInBetweenBranches(withdrawBranchesForChildTokens[msg.sender][i], childReality,branchForWithdraw));
		}
		uint amount = buyChildOrders[msg.sender]*totalBuyParentTokenVolume/totalBuyChildTokenVolume;
		realityToken.transfer(msg.sender, amount, branchForWithdraw);

		if(gasEfficient)
			buyChildOrders[msg.sender]=0;
		else{
			withdrawBranchesForChildTokens[msg.sender].push(branchForWithdraw);
		}	
	}

	function isAuctionClosed()
	public returns (bool){
		return (now-timeOfCreation)/ONE_TRADE_PERIOD>6;
	}
	function max(uint a, uint b)
	public pure returns(uint){
		if(a>b)
		return a;
		else return b;
	}
}