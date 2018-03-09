pragma solidity ^0.4.18;
import "./RealityToken.sol";

contract RealityMarketInterface{
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
	    
	    uint constant ONETRADEPERIOD=(1 days);

	    mapping (address => bytes32[]) withdrawBranchesForChildTokens;
	    mapping (address => bytes32[]) withdrawBranchesForParentTokens;


	function initializeAuction(uint amount, bytes32 childReality_, bytes32 parentReality_, address realityToken_, address sender)
	public;
}