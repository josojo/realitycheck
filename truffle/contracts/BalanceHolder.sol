pragma solidity ^0.4.18;

import "./RealityToken.sol";

contract BalanceHolder {

    mapping(address => bytes32 => uint256) public balanceOf;

    function BalanceHolder(address realityToken_){
        RT = RealityToken(realityToken_);
    }

    event LogWithdraw(
        address indexed user,
        uint256 amount
    );

    function withdraw(bytes32 branch_) 
    public {
        uint256 bal = balanceOf[branch_][msg.sender];
        balanceOf[branch_][msg.sender] = 0;
        RT.transfer(msg.sender, bal, branch_);
        LogWithdraw(msg.sender, bal);
    }

}
