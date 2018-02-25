pragma solidity ^0.4.18;

import './SafeMath.sol';
import './DataContract.sol';

contract RealityToken {

    using SafeMath for uint256;

    event Approval(address indexed _owner, address indexed _spender, uint _value, bytes32 branch);
    event Transfer(address indexed _from, address indexed _to, uint _value, bytes32 branch);
    event BranchCreated(bytes32 hash, address data_cntrct);


    string public constant name = "Reality-Token";
    string public constant symbol = "RLT";
    uint8 public constant decimals = 18;  // 18 is the most common number of decimal places

    bytes32 public constant NULL_HASH = "";
    address public constant NULL_ADDRESS = 0x0;

    struct Branch {
        bytes32 parent_hash; // Hash of the parent branch.
        bytes32 merkle_root; // Merkle root of the data we commit to
        address data_cntrct; // Optional address of a contract containing this data
        uint256 timestamp; // Timestamp branch was mined
        uint256 window; // Day x of the system's operation, starting at UTC 00:00:00
        mapping(address => int256) balance_change; // user debits and credits
    }
    mapping(bytes32 => Branch) public branches;

    // Spends, which may cause debits, can only go forwards.
    // That way when we check if you have enough to spend we only have to go backwards.
    mapping(address => uint256) public last_debit_windows; // index of last user debits to stop you going backwards
    // index to easily get all branch hashes for a window
    mapping(uint256 => bytes32[]) public window_branches; 
    // 00:00:00 UTC on the day the contract was mined
    uint256 public genesis_window_timestamp; 

    // allowanceFrom => allowanceTo => onBranch => amount
    mapping(address => mapping(address => mapping(bytes32=> uint256))) allowed;

    bytes32 public genesis_branch;
    function RealityToken(address initalDistribution, address initialDataContract)
    public {
        genesis_window_timestamp = now - (now % 86400);
        bytes32 genesis_merkle_root = keccak256("I leave to several futures (not to all) my garden of forking paths");
        bytes32 genesis_branch_hash = keccak256(NULL_HASH, genesis_merkle_root, NULL_ADDRESS);
        branches[genesis_branch_hash] = Branch(NULL_HASH, genesis_merkle_root, initialDataContract, now, 0);
        branches[genesis_branch_hash].balance_change[initalDistribution] = 210000000000000000000000000 ;
        window_branches[0].push(genesis_branch_hash);
        genesis_branch = genesis_branch_hash;
    }

    // arbitrationCosts are managed via subjectiviocracy and the DataContract. 
    // An update of the charged arbitration costs will first undergo a informal process of finding consensus within the community and then get included into
    // the next AnswerContract. 
    function getRealityArbitrationCosts(bytes32 hash) public view returns(uint arbitrationCost){
        while(arbitrationCost == 0)
        {
            arbitrationCost = DataContract(branches[hash].data_cntrct).realityArbitrationCost();
            hash = branches[hash].parent_hash;
        }
        return arbitrationCost;
    }

    // cheap way to preregister a branch that one wants to submit. Only clients will be able to process this information and make 
    // decisions on where a branch was submitted correctly and whether it should be the selected branch if several branches with the samae answers are submitted
    event Preregisiter(bytes32 parent_branch_hash, bytes32 hashOfAllAnsweredQuestionHashes, bytes32 hashOfAllAnswersSubmitted, address sender);
    function prerequisterNewBranch(bytes32 parent_branch_hash, bytes32 hashOfAllAnsweredQuestionHashes, bytes32 hashOfAllAnswersSubmitted)
    public {
        Preregisiter(parent_branch_hash, hashOfAllAnsweredQuestionHashes, hashOfAllAnswersSubmitted, msg.sender);
    }

    //@dev addition of a new branch on the system. if there are seleveral branches with the same answers, a metric will decide on which branch should be the selected one
    //@param parent_branch_hash is the branch of the previous parent hash
    //@param merkle_root is the merkle_root of the first inital branch
    //@param data_cntrct is the contract containing the data for the new branch
    function createBranch(bytes32 parent_branch_hash, bytes32 merkle_root, address data_cntrct, uint256 commitmentFund, uint rewardFund)
    public returns (bytes32) {
        uint256 window = (now - genesis_window_timestamp) / 86400; // NB remainder gets rounded down

        bytes32 branch_hash = keccak256(parent_branch_hash, merkle_root, data_cntrct);
        require(branch_hash != NULL_HASH);

        // Your branch must not yet exist, the parent branch must exist.
        // Check existence by timestamp, all branches have one.
        require(branches[branch_hash].timestamp == 0);
        require(branches[parent_branch_hash].timestamp > 0);

        // We must now be a later 24-hour window than the parent.
        require(branches[parent_branch_hash].window < window);

        // add a cost for a false branch, but also reward in case the branch gets accepted
        require(transfer(address(0), commitmentFund, parent_branch_hash));
        branches[branch_hash].balance_change[msg.sender] += int(rewardFund);

        // distribute further RealityTokens when requested in the data_cntrct via subjectiviocracy
        DataContract DC = DataContract(data_cntrct);
        int amount = DC.fundedAmount();
        if (amount > 0) {
            branches[branch_hash].balance_change[DC.fundedContract()] += amount;

        }

        branches[branch_hash] = Branch(parent_branch_hash, merkle_root, data_cntrct, now, window);
        window_branches[window].push(branch_hash);
        BranchCreated(branch_hash, data_cntrct);
        
        // a score for the createdBranch will only be calculated on the client side.
        // a proposal would be:
        // uint256 (sha256(branch_hash,data_contract, parent_branch_hash)) *balanceOf(msg.sender, parent_branch_hash) 
        
        return branch_hash;
    }

    function getWindowBranches(uint256 window)
    public constant returns (bytes32[]) {
        return window_branches[window];
    }

    function approve(address _spender, uint256 _amount, bytes32 _branch)
    public returns (bool success) {
        allowed[msg.sender][_spender][_branch] = _amount;
        Approval(msg.sender, _spender, _amount, _branch);
        return true;
    }

    function allowance(address _owner, address _spender, bytes32 branch)
    public constant returns (uint remaining) {
        return allowed[_owner][_spender][branch];
    }

    function balanceOf(address addr, bytes32 branch)
    public constant returns (uint256) {
        int256 bal = 0;
        while (branch != NULL_HASH) {
            bal += branches[branch].balance_change[addr];
            branch = branches[branch].parent_hash;
        }
        return uint256(bal);
    }

    function getParentBranch(bytes32 branch)
    public view returns (bytes32){
        return branches[branch].parent_hash;
    }
    // Crawl up towards the root of the tree until we get enough, or return false if we never do.
    // You never have negative total balance above you, so if you have enough credit at any point then return.
    // This uses less gas than balanceOfAbove, which always has to go all the way to the root.
    function isAmountSpendable(address addr, uint256 _min_balance, bytes32 branch_hash)
    public constant returns (bool) {
        require(_min_balance <= 210000000000000000000000000);
        int256 bal = 0;
        int256 min_balance = int256(_min_balance);
        while (branch_hash != NULL_HASH) {
            bal += branches[branch_hash].balance_change[addr];
            branch_hash = branches[branch_hash].parent_hash;
            if (bal >= min_balance) {
                return true;
            }
        }
        return false;
    }

    function transferFrom(address from, address addr, uint256 amount, bytes32 branch)
    public returns (bool) {

        require(allowed[from][msg.sender][branch] >= amount);

        uint256 branch_window = branches[branch].window;

        require(amount <= 210000000000000000000000000);
        require(branches[branch].timestamp > 0); // branch must exist

        if (branch_window < last_debit_windows[from]) return false; // debits can't go backwards
        if (!isAmountSpendable(from, amount, branch)) return false; // can only spend what you have

        last_debit_windows[from] = branch_window;
        branches[branch].balance_change[from] -= int256(amount);
        branches[branch].balance_change[addr] += int256(amount);

        uint256 allowed_before = allowed[from][msg.sender][branch];
        uint256 allowed_after = allowed_before - amount;
        assert(allowed_before > allowed_after);

        Transfer(from, addr, amount, branch);

        return true;
    }

    function transfer(address addr, uint256 amount, bytes32 branch)
    public returns (bool) {
        uint256 branch_window = branches[branch].window;

        require(amount <= 210000000000000000000000000);
        require(branches[branch].timestamp > 0); // branch must exist

        if (branch_window < last_debit_windows[msg.sender]) return false; // debits can't go backwards
        if (!isAmountSpendable(msg.sender, amount, branch)) return false; // can only spend what you have

        last_debit_windows[msg.sender] = branch_window;
        branches[branch].balance_change[msg.sender] -= int256(amount);
        branches[branch].balance_change[addr] += int256(amount);

        Transfer(msg.sender, addr, amount, branch);

        return true;
    }

    function getDataContract(bytes32 _branch)
    public constant returns (address) {
        return branches[_branch].data_cntrct;
    }

    function getWindowOfBranch(bytes32 _branchHash)
    public constant returns (uint id) {
        return branches[_branchHash].window;
    }

    function isBranchInBetweenBranches(bytes32 investigationHash, bytes32 closerToRootHash, bytes32 fartherToRootHash)
    public constant returns (bool) {
        bytes32 iterationHash = fartherToRootHash;
        while (iterationHash != closerToRootHash) {
            if (investigationHash == iterationHash) {
                return true;
            } else {
                iterationHash = branches[iterationHash].parent_hash;
            }
        }
        return false;
    }

}