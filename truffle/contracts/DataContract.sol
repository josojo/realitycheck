pragma solidity ^0.4.15;

contract DataContract{
   mapping(bytes32 => bytes32) answersBytes;
   mapping(bytes32 => bool) answerGiven;
   address public realityToken;
   address public owner;
   bool isFinished;
   uint public realityArbitrationCost;  
   address public fundedContract;
   int public fundedAmount;

   event Answer(bytes32 hashid, bytes32 answer);
   event AdditionalSupportedDapp(address);
   event UnSupportedDapp(address);

   modifier isOwner(){
    require(msg.sender == owner);
    _;
   }


   modifier notYetFinished(){
    require(!isFinished);
    _;
   }

   //Constructor sets the owner of the DataContract
   //@param additionalSupportedDapps  adds a additional Dapps to the list of supported Dapps
   //@param noLongerSupportedDapps list of dapps, which should no longer supported
   function DataContract()
   public {
     owner = msg.sender;
   }

   function unSupportDapp( address[] noLongerSupportedDapps)
   public {
     for(uint i=0;i<noLongerSupportedDapps.length;i++)
     {
       UnSupportedDapp(noLongerSupportedDapps[i]);
    }
   }

   function SupportDapp(address[] additionalSupportedDapps)
   public {
     for(uint i=0;i<additionalSupportedDapps.length;i++)
     {
       AdditionalSupportedDapp(additionalSupportedDapps[i]);
      }
   }
   // allows to inflace the realityTokenSupply
   //@param fundedContract allows to hand over a contract which holds the amounts and address which should get them
   //@param fundAmount is the total of all realityToken funds created for all accounts specified in the fundedContract_
   function injectFunding(address fundedContract_, int fundAmount_)
   isOwner()
   notYetFinished()
   public
   {
     fundedContract = fundedContract_;
     fundedAmount = fundAmount_;
   }

   // allows to set a new setArbitrationCost
   // @param cost_ the cost for all future arbitration costs needed to pay before we start a new window.
   function setArbitrationCost(uint cost_)
   isOwner()
   notYetFinished()
   public 
   {
      realityArbitrationCost = cost_;
   }

   //all answeres needs to be added one after another;
   function addAnswer(bytes32[] hashid_, bytes32[] answer_)
   isOwner()
   notYetFinished()
   public
   {
      for(uint i=0;i<hashid_.length;i++){
        answersBytes[hashid_[i]] = answer_[i];
        answerGiven[hashid_[i]] = true;  
        Answer(hashid_[i], answer_[i]);
      }
    }

   function finalize()
   isOwner()
   public{
     isFinished = true;
   }

   function getAnswer(bytes32 hashid_) constant public returns (bytes32){
     require(answerGiven[hashid_]);
     return answersBytes[hashid_];
   }
}