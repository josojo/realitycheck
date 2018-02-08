pragma solidity ^0.4.15;

contract DataContract{
   mapping(bytes32 => bytes32) answersBytes;
   mapping(bytes32 => bool) answerGiven;
   address public realityToken;
   address public owner;
   bool isFinished;

   modifier isOwner(){
    require(msg.sender == owner);
    _;
   }


   modifier notYetFinished(){
    require(isFinished);
    _;
   }

   //Constructor sets the owner of the DataContract
   function DataContract()
   public {
     owner=msg.sender;
   }

   //all answeres needs to be added one after another;
   function addAnswer(bytes32 hashid_, bytes32 answer_)
   isOwner()
   notYetFinished()
   public
   {
     answersBytes[hashid_] = answer_;
     answerGiven[hashid_]=true;
   }

   function finalize()
   isOwner()
   public{
     isFinished=true;
   }

   function getAnswer(bytes32 hashid_) constant public returns (bytes32){
     require(answerGiven[hashid_]);
     return answersBytes[hashid_];
   }
}