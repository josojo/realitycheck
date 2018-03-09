pragma solidity ^0.4.18;

import './SafeMath.sol';
import './SafeMath32.sol';
import './RealityToken.sol';
import './DataContract.sol';
import './RealityMarket.sol';
import "@gnosis.pm/gnosis-core-contracts/contracts/Tokens/StandardToken.sol";

contract InitialLendingContract {
	using SafeMath for uint;
	bytes32 public intializationBranch;
	mapping (uint => bytes32[]) public withdrawBranches;
	StandardToken public etherToken;
	RealityToken public realityToken;
	uint public lendingPriceEthNum = 1;
	uint public lendingPriceEthDen = 100;
	uint constant collateralRatio = 2;

	mapping(address => uint) public providers;
	mapping(address => uint) public lenders;
	uint fee = 200;

	uint public deadlineForReturning;
	uint public lastWindowForReturning;

	address owner;

	function InitialLendingContract(bytes32 intializationBranch_, StandardToken etherToken_, RealityToken realityToken_)
		public 
	{
		owner = msg.sender;
		intializationBranch = intializationBranch_;
		etherToken = etherToken_;
		realityToken = realityToken_;
		deadlineForReturning = now + 300 days;
		lastWindowForReturning = (deadlineForReturning - realityToken.genesis_window_timestamp()) / realityToken.windowPeriod()
						 -((deadlineForReturning - realityToken.genesis_window_timestamp()) / realityToken.windowPeriod() % 10); 
	}
	// @dev allows to lend tokens from this contract in exchange for collateral ether. 
	//@dev Tokens can be return later to get the collateral back
	//@param amount is the amount of RealityTokens someone wants to lend
	function lend(uint amount) 
		public
	{
		require(etherToken.transferFrom(msg.sender, this, amount *collateralRatio / lendingPriceEthDen));
		lenders[msg.sender]+= amount;
		require(realityToken.transfer(msg.sender, amount, intializationBranch));
	}


	//@dev allows to return RealityTokens previously rented out and get the collateral back
	//@param amount is the amount of RealityTokens to be returned
	//@param window is the particular window from the RealityToken contract for which the RealityTokens should be returned
	function returnRealityTokens(uint amount, uint window)
		public
	{
		require(window%10 == 0);
		require(now>realityToken.genesis_window_timestamp()+realityToken.windowPeriod()*window);
		for(uint i=0;i<withdrawBranches[window].length;i++){
			require(realityToken.transferFrom(msg.sender, this, amount, withdrawBranches[window][i]));
		}
		lenders[msg.sender] = lenders[msg.sender].sub(amount);
		require(etherToken.transfer(msg.sender, amount));
	}

	//@dev allows to specify branches of the realityTokens, for which RealityTokens needs to be handed in for returning them to the lending contract
	//@dev branches  can only be added if the price of the token is higher than a threshold of 0.6
	//@param branches are the branches to be added
	//@param window is the window for which the branches should be added
	function addBranchForWindow(bytes32[] branches, uint window)
		public
	{
		require(window%10 == 0);
		require(now<realityToken.genesis_window_timestamp()+realityToken.windowPeriod()*window);		
		for(uint i=0; i<branches.length; i++){
			bytes32 branch = branches[i];
			require(realityToken.getWindowOfBranch(branch) == window);
			//check that branch is legitiate branch, ie. price is higher than 0.6 between all his parents and childs
			while(branch != intializationBranch){
				bytes32 parentbranch = realityToken.getParentBranch(branch);
				RealityMarket market = RealityMarket(realityToken.getAuctionMarketForBranch(branch));
				require(market.isAuctionClosed());
				uint priceNum = market.totalBuyChildTokenVolume();
		    	uint priceDen = market.totalBuyParentTokenVolume();
				require(priceNum >= priceDen * 3/5);
				branch = parentbranch;
			}
			bool alreadyExisting = false;
			for(uint j=0;j<withdrawBranches[window].length;j++){
				if(branch == withdrawBranches[window][j]){
					alreadyExisting = true;
					break;
				}
			}
			if(!alreadyExisting)
			withdrawBranches[window].push(branch);
		}
	}

	//@dev allows the ReailtyToken posessors to deposit in here to lend them out to others.
	//@param amount is the amount of RealityToekns a depositor wants to provide
	function provideRealityTokens(uint amount) 
		public
	{
		require(realityToken.transferFrom(msg.sender, this, amount, intializationBranch));
		providers[msg.sender]+=amount;
	}
	//@dev allows to depositors of RealityTokens to get them back, if available. 
	function retrieveRealityTokens(uint amount, uint window) 
		public
	{
		require(withdrawBranches[window].length>0);
		amount = max(amount, providers[msg.sender]);
		providers[msg.sender] = providers[msg.sender].sub(amount);
		for(uint i=0;i<withdrawBranches[window].length;i++){
			require(realityToken.transfer(msg.sender, amount, withdrawBranches[window][i]));
		}
	}
	//@dev allows to depositors of RealityTokens to get the collateral back, in case RealityTokens were not returned 
	function getCollateral()
		public
	{
		require(now>deadlineForReturning);
		//checkThatReturningIsNotPossible
		uint amountRealityTokens = providers[msg.sender];
		uint window = lastWindowForReturning;
		uint payableInRealityTokens= amountRealityTokens;
		for(uint i=0;i<withdrawBranches[window].length;i++){
			payableInRealityTokens = min(payableInRealityTokens, realityToken.balanceOf(this, withdrawBranches[window][i]));
		}	
		retrieveRealityTokens(amountRealityTokens, window);
		uint amountToReturn = amountRealityTokens - payableInRealityTokens;
		etherToken.transfer(msg.sender, amountToReturn * collateralRatio / lendingPriceEthDen); 
	}

	function min(uint a, uint b)
		public 
		returns (uint)
	{
		if(a<b)return a;
		else return b;
	}
	function max(uint a, uint b)
		public 
		returns (uint)
	{
		if(a>b)return a;
		else return b;
	}
}