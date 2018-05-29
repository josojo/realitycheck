pragma solidity ^0.4.18;

import './SafeMath.sol';
import './SafeMath32.sol';
import './RealityToken.sol';
import './DataContract.sol';


contract RealityCheck {

    using SafeMath for uint256;
    using SafeMath32 for uint32;

    RealityToken realityToken;


    address constant NULL_ADDRESS = address(0);

    // History hash when no history is created, or history has been cleared
    bytes32 constant NULL_HASH = bytes32(0);

    // An unitinalized finalize_ts for a question will indicate an unanswered question.
    uint32 constant UNANSWERED = 0;

    // An unanswered reveal_ts for a commitment will indicate that it does not exist.
    uint256 constant COMMITMENT_NON_EXISTENT = 0;

    // Commit->reveal timeout is 1/8 of the question timeout (rounded down).
    uint32 constant COMMITMENT_TIMEOUT_RATIO = 8;

    // 
    uint constant ARBITRATOR_ANSWER_IS_MISSING = 0;

    event LogSetQuestionFee(
        address arbitrator,
        uint256 amount
    );

    event LogNewTemplate(
        uint256 indexed template_id,
        address indexed user, 
        string question_text
    );

    event LogNewQuestion(
        bytes32 indexed question_id,
        address indexed user, 
        uint256 template_id,
        string question,
        bytes32 indexed content_hash,
        uint32 timeout,
        uint32 opening_ts,
        uint256 nonce,
        uint256 created,
        uint256 amount,
        bytes32 branch
    );

    event LogFundAnswerBounty(
        bytes32 indexed question_id,
        uint256 bounty_added,
        uint256 bounty,
        address indexed user,
        bytes32 branch

    );

    event LogNewAnswer(
        bytes32 answer,
        bytes32 indexed question_id,
        bytes32 history_hash,
        address indexed user,
        uint256 bond,
        uint256 ts,
        bool is_commitment
    );

    event LogAnswerReveal(
        bytes32 indexed question_id, 
        address indexed user, 
        bytes32 indexed answer_hash, 
        bytes32 answer, 
        uint256 nonce, 
        uint256 bond
    );

    event LogNotifyOfArbitrationRequest(
        bytes32 indexed question_id,
        address indexed user 
    );

    event LogFinalize(
        bytes32 indexed question_id,
        bytes32 indexed answer
    );

    event LogClaim(
        bytes32 indexed question_id,
        address indexed user,
        uint256 amount,
        bytes32 branch
    );

    struct Question {
        bytes32 content_hash;
        uint arbitrator;
        uint32 opening_ts;
        uint32 timeout;
        uint32 finalize_ts;
        bool is_pending_arbitration_from_arbitrator;
        bool endOfChallengingPeriodForRealityToken;
        bool is_pending_arbitration_from_realityToken;
        uint256 bounty;
        bytes32 best_answer;
        bytes32 history_hash;
        uint256 bond;
        bytes32 branch;
        // branch => lastHashWithdrawn
        bytes32[] realityWithdrawBranches;
    }

    // Stored in a mapping indexed by commitment_id, a hash of commitment hash, question, bond. 
    struct Commitment {
        uint32 reveal_ts;
        bool is_revealed;
        bytes32 revealed_answer;
    }

    // Only used when claiming more bonds than fits into a transaction
    // Stored in a mapping indexed by question_id.
    struct Claim {
        address payee;
        uint256 last_bond;
        uint256 queued_funds;
        bytes32 history_hash;
    }

    uint256 nextTemplateID = 0;
    mapping(uint256 => uint256) public templates;
    mapping(bytes32 => Question) public questions;
    mapping(bytes32 => mapping( bytes32 => Question)) public questions_branched;

    mapping(bytes32 => mapping( bytes32 => Claim)) question_claims;
    mapping(bytes32 => Commitment) public commitments;
    uint public arbitrator_question_fees; 


    modifier onlyArbitrator(bytes32 question_id) {
        require(msg.sender == questions[question_id].arbitrator);
        _;
    }

    modifier stateAny() {
        _;
    }

    modifier stateNotCreated(bytes32 question_id) {
        require(questions[question_id].timeout == 0);
        _;
    }


    modifier stateOpen(bytes32 question_id) {
        require(questions[question_id].timeout > 0); // Check existence
        require(!questions[question_id].is_pending_arbitration);
        // TODO :uint32 finalize_ts = ;
        require(questions[question_id].finalize_ts == UNANSWERED || questions[question_id].finalize_ts > uint32(now));
        // TODO opening_ts =
        require(questions[question_id].opening_ts == 0 || questions[question_id].opening_ts <= uint32(now)); 
        _;
    }

    modifier statePendingArbitration(bytes32 question_id) {
        require(questions[question_id].is_pending_arbitration);
        _;
    }

    modifier stateFinalized(bytes32 question_id) {
        require(isFinalized(question_id));
        _;
    }

    modifier bondMustBeZero(uint amount) {
        require(amount == 0);
        _;
    }

    modifier bondMustDouble(bytes32 question_id, uint amount) {
        require(amount > 0); 
        require(amount >= (questions[question_id].bond.mul(2)));
        _;
    }

    modifier previousBondMustNotBeatMaxPrevious(bytes32 question_id, uint256 max_previous) {
        if (max_previous > 0) {
            require(questions[question_id].bond <= max_previous);
        }
        _;
    }

    /// @notice Constructor, sets up some initial templates
    /// @dev Creates some generalized templates for different question types used in the DApp.
    function RealityCheck(address realityToken_, uint256 feeForRealityToken) 
    public {
        realityToken = RealityToken(realityToken_);
        arbitrator_question_fees = feeForRealityToken;

        createTemplate('{"title": "%s", "type": "bool", "category": "%s"}');
        createTemplate('{"title": "%s", "type": "uint", "decimals": 18, "category": "%s"}');
        createTemplate('{"title": "%s", "type": "int", "decimals": 18, "category": "%s"}');
        createTemplate('{"title": "%s", "type": "single-select", "outcomes": [%s], "category": "%s"}');
        createTemplate('{"title": "%s", "type": "multiple-select", "outcomes": [%s], "category": "%s"}');
        createTemplate('{"title": "%s", "type": "datetime", "category": "%s"}');
    }


    /// @notice Create a reusable template, which should be a JSON document.
    /// Placeholders should use gettext() syntax, eg %s.
    /// @dev Template data is only stored in the event logs, but its block number is kept in contract storage.
    /// @param content The template content
    /// @return The ID of the newly-created template, which is created sequentially.
    function createTemplate(string content) 
    stateAny()
    public returns (uint256) {
        uint256 id = nextTemplateID;
        templates[id] = block.number;
        LogNewTemplate(id, msg.sender, content);
        nextTemplateID = id.add(1);
        return id;
    }

    /// @notice Create a new reusable template and use it to ask a question
    /// @dev Template data is only stored in the event logs, but its block number is kept in contract storage.
    /// @param content The template content
    /// @param question A string containing the parameters that will be passed into the template to make the question
    /// @param timeout How long the contract should wait after the answer is changed before finalizing on that answer
    /// @param opening_ts If set, the earliest time it should be possible to answer the question.
    /// @param nonce A user-specified nonce used in the question ID. Change it to repeat a question.
    /// @return The ID of the newly-created template, which is created sequentially.
    function createTemplateAndAskQuestion(
        string content, 
        string question,
        uint32 timeout,
        uint32 opening_ts,
        uint256 nonce,
        uint amount,
        bytes32 branch,
        uint arbitrator  
    ) 
        // stateNotCreated is enforced by the internal _askQuestion
    public returns (bytes32) {
        uint256 template_id = createTemplate(content);
        return askQuestion(template_id, question, timeout, opening_ts, nonce, amount, branch, arbitrator);
    }

    /// @notice Ask a new question and return the ID
    /// @dev Template data is only stored in the event logs, but its block number is kept in contract storage.
    /// @param template_id The ID number of the template the question will use
    /// @param question A string containing the parameters that will be passed into the template to make the question
    /// @param timeout How long the contract should wait after the answer is changed before finalizing on that answer
    /// @param opening_ts If set, the earliest time it should be possible to answer the question.
    /// @param nonce A user-specified nonce used in the question ID. Change it to repeat a question.
    /// @return The ID of the newly-created question, created deterministically.
    function askQuestion(uint256 template_id, string question, uint32 timeout, uint32 opening_ts, uint256 nonce, uint amount, bytes32 branch, uint arbitratorNr) 
        // stateNotCreated is enforced by the internal _askQuestion
    public returns (bytes32) {

        require(templates[template_id] > 0); // Template must exist

        bytes32 content_hash = keccak256(template_id, opening_ts, question);
        bytes32 question_id = keccak256(content_hash, timeout, msg.sender, nonce, branch, arbitrator);

        _askQuestion(question_id, content_hash, timeout, opening_ts, amount, branch, arbitrator);
        LogNewQuestion(question_id, msg.sender, template_id, question, content_hash, timeout, opening_ts, nonce, now, amount, branch);

        return question_id;
    }

    function _askQuestion(
        bytes32 question_id,
        bytes32 content_hash,
        uint32 timeout,
        uint32 opening_ts,
        uint amount,
        bytes32 branch,
        uint arbitrator
    ) 
    stateNotCreated(question_id)
    internal 
    {

        // A timeout of 0 makes no sense, and we will use this to check existence
        require(timeout > 0); 
        require(timeout < 365 days); 
        require(realityToken.transferFrom(msg.sender, this, amount, branch));
        uint bounty = amount;
        
        // The arbitrator can set a fee for asking a question. 
        // This is intended as an anti-spam defence.
        // The fee is waived if the arbitrator is asking the question.
        // This allows them to set an impossibly high fee and make users proxy the question through them.
        // This would allow more sophisticated pricing, question whitelisting etc.
        
        uint256 question_fee = arbitrator_question_fees;
        require(bounty >= question_fee); 
        bounty = bounty.sub(question_fee);
        
        questions[question_id].content_hash = content_hash;
        questions[question_id].opening_ts = opening_ts;
        questions[question_id].timeout = timeout;
        questions[question_id].bounty = bounty;
        questions[question_id].branch = branch;
        questions[question_id].arbitrator = arbitrator;

    }

    /// @notice Add funds to the bounty for a question
    /// @dev Add bounty funds after the initial question creation. Can be done any time until the question is finalized.
    /// @param question_id The ID of the question you wish to fund
    function fundAnswerBounty(bytes32 question_id, uint amount, bytes32 content_hash, bytes32 branch) 
        stateOpen(question_id)
    external {
        require(realityToken.transferFrom(msg.sender, this, amount, questions[question_id].branch));

        questions[question_id].bounty = questions[question_id].bounty.add(amount);
        LogFundAnswerBounty(question_id, amount, questions[question_id].bounty, msg.sender, branch);
    }

    /// @notice Submit an answer for a question.
    /// @dev Adds the answer to the history and updates the current "best" answer.
    /// May be subject to front-running attacks; Substitute submitAnswerCommitment()->submitAnswerReveal() to prevent them.
    /// @param question_id The ID of the question
    /// @param answer The answer, encoded into bytes32
    /// @param max_previous If specified, reverts if a bond higher than this was submitted after you sent your transaction.
    function submitAnswer(bytes32 question_id, bytes32 answer, uint256 max_previous, uint amount) 
        stateOpen(question_id)
        bondMustDouble(question_id, amount)
        previousBondMustNotBeatMaxPrevious(question_id, max_previous)
    external{
        require(realityToken.transferFrom(msg.sender, this, amount, questions[question_id].branch));
        _addAnswerToHistory(question_id, answer, msg.sender, amount, false);
        _updateCurrentAnswer(question_id, answer, questions[question_id].timeout);
    }

    /// @notice Submit the hash of an answer, laying your claim to that answer if you reveal it in a subsequent transaction.
    /// @dev Creates a hash, commitment_id, uniquely identifying this answer, to this question, with this bond.
    /// The commitment_id is stored in the answer history where the answer would normally go.
    /// Does not update the current best answer - this is left to the later submitAnswerReveal() transaction.
    /// @param question_id The ID of the question
    /// @param answer_hash The hash of your answer, plus a nonce that you will later reveal
    /// @param max_previous If specified, reverts if a bond higher than this was submitted after you sent your transaction.
    /// @param _answerer If specified, the address to be given as the question answerer. Defaults to the sender.
    /// @dev Specifying the answerer is useful if you want to delegate the commit-and-reveal to a third-party.
    function submitAnswerCommitment(bytes32 question_id, bytes32 answer_hash, uint bond, uint256 max_previous, address _answerer) 
        stateOpen(question_id)
        bondMustDouble(question_id, bond)
        //previousBondMustNotBeatMaxPrevious(question_id, max_previous)
    external payable {
        require(realityToken.transferFrom(msg.sender, this, bond, questions[question_id].branch));

        bytes32 commitment_id = keccak256(question_id, answer_hash, bond);

        require(commitments[commitment_id].reveal_ts == COMMITMENT_NON_EXISTENT);
        commitments[commitment_id].reveal_ts = uint32(now).add(questions[question_id].timeout / COMMITMENT_TIMEOUT_RATIO);

        _addAnswerToHistory(question_id, commitment_id, ((_answerer == NULL_ADDRESS) ? msg.sender : _answerer), bond, true);

    }

    /// @notice Submit the answer whose hash you sent in a previous submitAnswerCommitment() transaction
    /// @dev Checks the parameters supplied recreate an existing commitment, and stores the revealed answer
    /// Updates the current answer unless someone has since supplied a new answer with a higher bond
    /// msg.sender is intentionally not restricted to the user who originally sent the commitment; 
    /// For example, the user may want to provide the answer+nonce to a third-party service and let them send the tx
    /// @param question_id The ID of the question
    /// @param answer The answer, encoded as bytes32
    /// @param nonce The nonce that, combined with the answer, recreates the answer_hash you gave in submitAnswerCommitment()
    /// @param bond The bond that you paid in your submitAnswerCommitment() transaction
    function submitAnswerReveal(bytes32 question_id, bytes32 answer, uint256 nonce, uint256 bond) 
        stateOpen(question_id)
    external {

        bytes32 answer_hash = keccak256(answer, nonce);
        bytes32 commitment_id = keccak256(question_id, answer_hash, bond);

        require(!commitments[commitment_id].is_revealed);
        require(commitments[commitment_id].reveal_ts > uint32(now)); // Reveal deadline must not have passed

        commitments[commitment_id].revealed_answer = answer;
        commitments[commitment_id].is_revealed = true;

        if (bond == questions[question_id].bond) {
            _updateCurrentAnswer(question_id, answer, questions[question_id].timeout);
        }

        LogAnswerReveal(question_id, msg.sender, answer_hash, answer, nonce, bond);

    }

    function _addAnswerToHistory(bytes32 question_id, bytes32 answer_or_commitment_id, address answerer, uint256 bond, bool is_commitment) 
    internal 
    {
        bytes32 new_history_hash = keccak256(questions[question_id].history_hash, answer_or_commitment_id, bond, answerer, is_commitment);

        questions[question_id].bond = bond;
        questions[question_id].history_hash = new_history_hash;

        LogNewAnswer(answer_or_commitment_id, question_id, new_history_hash, answerer, bond, now, is_commitment);
    }

    function _updateCurrentAnswer(bytes32 question_id, bytes32 answer, uint32 timeout_secs)
    internal {
        questions[question_id].best_answer = answer;
        questions[question_id].finalize_ts = uint32(now).add(timeout_secs);
    }



    /// @notice Notify the contract that the arbitrator has been paid for a question, freezing it pending their decision.
    /// @dev The arbitrator contract is trusted to only call this if they've been paid, and tell us who paid them.
    /// @param question_id The ID of the question
    /// @param requester The account that requested arbitration
    function notifyOfArbitrationRequestFromArbitrator(bytes32 question_id, address requester) 
        onlyArbitrator(question_id)
        stateOpen(question_id)
    external {
        questions[question_id].is_pending_arbitration = true;
        LogNotifyOfArbitrationRequest(question_id, requester);
    }

    /// @notice Submit the answer for a question, for use by the arbitrator.
    /// @dev Doesn't require (or allow) a bond.
    /// If the current final answer is correct, the account should be whoever submitted it.
    /// If the current final answer is wrong, the account should be whoever paid for arbitration.
    /// However, the answerer stipulations are not enforced by the contract.
    /// @param question_id The ID of the question
    /// @param answer The answer, encoded into bytes32
    /// @param answerer The account credited with this answer for the purpose of bond claims
    function submitAnswerByArbitrator(bytes32 question_id, bytes32 answer, address answerer) 
        onlyArbitrator(question_id)
        statePendingArbitration(question_id)
        bondMustBeZero
    external {

        require(answerer != NULL_ADDRESS);
        LogFinalize(question_id, answer);
        questions[question_id].endOfChallengingPeriodForRealityToken = now + (5 days);
        questions[question_id].is_pending_arbitration_from_arbitrator = false;
        _addAnswerToHistory(question_id, answer, answerer, 0, false);
        _updateCurrentAnswer(question_id, answer, 0);

    }


    /// @notice Notify the contract that the minimal threshold for the realityToken to make a decision was reached
    /// @dev anyone can call this and request an arbitration from realityToken, if threshold of escalation is reached
    /// @param question_id The ID of the question
    function notifyOfArbitrationRequestRealityToken(bytes32 question_id) 
        stateStillChallengableWithRealityTokens(question_id)
    external {
        require( realityToken.transferFrom(msg.sender, this, realityToken.getRealityArbitrationCosts(questions[question_id].branch), questions[question_id].branch));
        questions[question_id].is_pending_arbitration_from_realityToken = true;
        LogNotifyOfArbitrationRequest(question_id, msg.sender);
    }

    

    /// @notice Report whether the answer to the specified question is finalized
    /// @param question_id The ID of the question
    /// @return Return true if finalized
    function isFinalized(bytes32 question_id, bytes32 branch) 
    constant public returns (bool) {
        uint32 finalize_ts = questions[question_id].finalize_ts;
        
        bool finalized = (questions[question_id].endOfChallengingPeriodForRealityToken <= now && !questions[question_id].is_pending_arbitration_from_arbitrator && (finalize_ts > UNANSWERED) && (finalize_ts <= uint32(now)) );
        if( finalized && !questions[question_id].is_pending_arbitration_from_realityToken)
            return true;
        else
            return false;    
    }

    /// @notice Report whether the answer to the specified question is finalized
    /// @param question_id The ID of the question
    /// @return Return true if finalized
    function isFinalizedOrUsingRealityArbitration(bytes32 question_id, bytes32 branch) 
    constant public returns (bool) {
        uint32 finalize_ts = questions[question_id].finalize_ts;
        
        bool finalized = (questions[question_id].endOfChallengingPeriodForRealityToken <= now && !questions[question_id].is_pending_arbitration_from_arbitrator && (finalize_ts > UNANSWERED) && (finalize_ts <= uint32(now)) );
        if( finalized   || questions[question_id].is_pending_arbitration_from_realityToken)
            return true;
        else
            {
            bool answerIsGivenByRealityToken;
            while(!answerIsGivenByRealityToken){
                address dataContract = realityToken.getDataContract(branch);
                answerIsGivenByRealityToken = DataContract(dataContract).isAnswerSet(question_id);
                if(!answerIsGivenByRealityToken){
                    branch = realityToken.getParentBranch(branch);
                    if( branch == realityToken.genesis_branch_hash())
                        return false;
                }  else{
                    return true;
                }

            }

            }   
    }

    /// @notice Return the final answer to the specified question, or revert if there isn't one
    /// @param question_id The ID of the question
    /// @return The answer formatted as a bytes32
    function getFinalAnswer( bytes32 branch, bytes32 question_id) 
    public constant returns (bytes32 best_answer) {
        uint32 finalize_ts = questions[question_id].finalize_ts;
        bool finalizedNormally = (!questions[question_id].is_pending_arbitration_from_arbitrator && (finalize_ts > UNANSWERED) && (finalize_ts <= uint32(now)) );
        if(finalized){
            best_answer = questions[question_id].best_answer;
        } else {
            bool answerIsGivenByRealityToken;
            while(!answerIsGivenByRealityToken){
                address dataContract = realityToken.getDataContract(branch);
                answerIsGivenByRealityToken = DataContract(dataContract).isAnswerSet(question_id);
                if(!answerIsGivenByRealityToken){
                    branch = realityToken.getParentBranch(branch);
                    require( branch != realityToken.genesis_branch_hash());
                }

            }
            best_answer = DataContract(dataContract).getAnswer(question_id);
    }

    /// @notice Return the final answer to the specified question, provided it matches the specified criteria.
    /// @dev Reverts if the question is not finalized, or if it does not match the specified criteria.
    /// @param question_id The ID of the question
    /// @param content_hash The hash of the question content (template ID + opening time + question parameter string)
    /// @param arbitrator The arbitrator chosen for the question (regardless of whether they are asked to arbitrate)
    /// @param min_timeout The timeout set in the initial question settings must be this high or higher
    /// @param min_bond The bond sent with the final answer must be this high or higher
    /// @return The answer formatted as a bytes32
    function getFinalAnswerIfMatches(
        bytes32 question_id, 
        bytes32 content_hash, address arbitrator, uint32 min_timeout, uint256 min_bond
    ) 
        stateFinalized(question_id)
    external constant returns (bytes32) {
        require(content_hash == questions[question_id].content_hash);
        require(arbitrator == questions[question_id].arbitrator);
        require(min_timeout <= questions[question_id].timeout);
        require(min_bond <= questions[question_id].bond);
        return questions[question_id].best_answer;
    }
    /// @notice Assigns the winnings (bounty and bonds) to everyone who gave the accepted answer
    /// Caller must provide the answer history, in reverse order
    /// @dev Works up the chain and assign bonds to the person who gave the right answer
    /// If someone gave the winning answer earlier, they must get paid from the higher bond
    /// That means we can't pay out the bond added at n until we have looked at n-1
    /// The first answer is authenticated by checking against the stored history_hash.
    /// One of the inputs to history_hash is the history_hash before it, so we use that to authenticate the next entry, etc
    /// Once we get to a null hash we'll know we're done and there are no more answers.
    /// Usually you would call the whole thing in a single transaction, but if not then the data is persisted to pick up later.
    /// @param question_id The ID of the question
    /// @param history_hashes Second-last-to-first, the hash of each history entry. (Final one should be empty).
    /// @param addrs Last-to-first, the address of each answerer or commitment sender
    /// @param bonds Last-to-first, the bond supplied with each answer or commitment
    /// @param answers Last-to-first, each answer supplied, or commitment ID if the answer was supplied with commit->reveal
    function claimWinnings(
        bytes32 branchForWithdraw,
        bytes32 branchFromPreviousWithdraw,
        bytes32 question_id, 
        bytes32[] history_hashes,
        address[] addrs,
        uint256[] bonds,
        bytes32[] answers
    ) 
    public {
        require(isFinalizedOrUsingRealityArbitration(question_id, branchForWithdraw));
        require(history_hashes.length > 0);
        //checks the eligibility of a branch for withdraw
        require(eligibleBranchForWithdraw(branchForWithdraw, branchFromPreviousWithdraw, question_id));
        
        // in the first run-through, we need to add the new branch to the tracked branchFromQuestion
        // inorder to prevent double withdraws.
        
        _setBranchInWithdrawHistory(branchForWithdraw, branchFromPreviousWithdraw, question_id);
        uint256 queued_funds = question_claims[question_id][branchFromPreviousWithdraw].queued_funds;
        address payee = question_claims[question_id][branchFromPreviousWithdraw].payee; 
         
        // These are only set if we split our claim over multiple transactions.
        uint256 last_bond = question_claims[question_id][branchFromPreviousWithdraw].last_bond; 
            
        bytes32 last_history_hash;
        if (branchFromPreviousWithdraw == bytes32(0))
            last_history_hash = questions[question_id].history_hash;
        else 
            last_history_hash = question_claims[question_id][branchFromPreviousWithdraw].history_hash;
        uint256 i;
        for (i = 0; i < history_hashes.length; i++) {
            
            // Check input against the history hash, and see which of 2 possible values of is_commitment fits.
            bool is_commitment =_verifyHistoryInputOrRevert(history_hashes[i], addrs[i], bonds[i], answers[i], last_history_hash);
            
             queued_funds = queued_funds.add(last_bond); 
               (queued_funds, payee) = _processHistoryItem(branchForWithdraw,
                    question_id, queued_funds, payee, 
                   addrs[i], bonds[i], answers[i], is_commitment);

            // Line the bond up for next time, when it will be added to somebody's queued_funds
            last_bond = bonds[i];
            last_history_hash = history_hashes[i];

        }
        if (last_history_hash != NULL_HASH) {
            // We haven't yet got to the null hash (1st answer), ie the caller didn't supply the full answer chain.
            // Persist the details so we can pick up later where we left off later.

            // If we know who to pay we can go ahead and pay them out, only keeping back last_bond
            // (We always know who to pay unless all we saw were unrevealed commits)
            if (payee != NULL_ADDRESS) {
                _payPayee   (branchForWithdraw, question_id,  queued_funds, payee);
                queued_funds = 0;
            }
            question_claims[question_id][branchForWithdraw].queued_funds = queued_funds;
            question_claims[question_id][branchForWithdraw].payee = payee;
            question_claims[question_id][branchForWithdraw].last_bond = last_bond;
        } else {
            // There is nothing left below us so the payee can keep what remains
            _payPayee(branchForWithdraw, question_id, queued_funds.add(last_bond), payee);
            delete question_claims[question_id][branchForWithdraw];
        }
 
        question_claims[question_id][branchForWithdraw].history_hash = last_history_hash;

    }

    // @dev: this function checks whether a branch is eligigble for a withdraw. 
    // if there is a closer parentbranch that the branchFromPreviousWithdraw we throw as well
    function eligibleBranchForWithdraw(bytes32 branchForWithdraw, bytes32 branchFromPreviousWithdraw, bytes32 question_id)
    public view returns(bool)
    {
        bytes32 branchFromQuestion = questions[question_id].branch;
        bytes32 [] alreadyUsedBranches = questions[question_id].realityWithdrawBranches;
        if(branchFromPreviousWithdraw!=bytes32(0)){ 
            // check that tokens were not yet withdrawn in inbetween branches
            for(uint i=0;i < alreadyUsedBranches.length;i++) {
                if(realityToken.isBranchInBetweenBranches(alreadyUsedBranches[i], branchFromPreviousWithdraw, branchForWithdraw))
                    return false;   
            }
        }
        // check that tokens will be withdrawn on a child branch of branch of question
        bytes32 branchParent = branchForWithdraw;
        while(branchParent != questions[question_id].branch){
            branchParent = realityToken.getParentBranch(branchParent);
            if(branchParent == bytes32(0))
                return false;
        }
        return true;
    }

    function _setBranchInWithdrawHistory(bytes32 branchForWithdraw, bytes32 branchFromPreviousWithdraw, bytes32 question_id)
    internal
    {
        if(branchFromPreviousWithdraw != branchForWithdraw)
           questions[question_id].realityWithdrawBranches.push(branchForWithdraw);         
        
    }


    function _payPayee(bytes32 branchForWithdraw, bytes32 question_id,  uint256 value, address payee) 
    internal {
        require(realityToken.transfer(payee, value, branchForWithdraw));
        LogClaim(question_id, payee, value, branchForWithdraw);
    }
    function _verifyHistoryInputOrRevert(
        bytes32 history_hash, address addr, uint256 bond, bytes32 answer,
        bytes32 last_history_hash
    )
    internal  returns (bool) {
        if (last_history_hash == keccak256(history_hash, answer, bond, addr, true) ) {
            return true;
        }
        if (last_history_hash == keccak256(history_hash, answer, bond, addr, false) ) {
            return false;
        } 
        revert();
    }

    function _processHistoryItem( bytes32 branchForWithdraw,
        bytes32 question_id, 
        uint256 queued_funds, address payee, 
        address addr, uint256 bond, bytes32 answer,
        bool is_commitment
    )
    internal returns (uint256, address) {
        bytes32 best_answer = getFinalAnswer(branchForWithdraw, question_id);
        // For commit-and-reveal, the answer history holds the commitment ID instead of the answer.
        // We look at the referenced commitment ID and switch in the actual answer.
        if (is_commitment) {
            bytes32 commitment_id = answer;
            // If it's a commit but it hasn't been revealed, it will always be considered wrong.
            if (!commitments[commitment_id].is_revealed) {
                return (queued_funds, payee);
            } else {
                answer = commitments[commitment_id].revealed_answer;
            }
        }

        if (answer == best_answer) {

            if (payee == NULL_ADDRESS) {

                // The entry is for the first payee we come to, ie the winner.
                // They get the question bounty.
                payee = addr;
                queued_funds = queued_funds.add(questions[question_id].bounty);
                
            } else if (addr != payee) {

                // Answerer has changed, ie we found someone lower down who needs to be paid

                // The lower answerer will take over receiving bonds from higher answerer.
                // They should also be paid the takeover fee, which is set at a rate equivalent to their bond. 
                // (This is our arbitrary rule, to give consistent right-answerers a defence against high-rollers.)

                // There should be enough for the fee, but if not, take what we have.
                // There's an edge case involving weird arbitrator behaviour where we may be short.
                uint256 answer_takeover_fee = (queued_funds >= bond) ? bond : queued_funds;

                // Settle up with the old (higher-bonded) payee
                _payPayee(branchForWithdraw, question_id, queued_funds.sub(answer_takeover_fee), payee);

                // Now start queued_funds again for the new (lower-bonded) payee
                payee = addr;
                queued_funds = answer_takeover_fee;

            }

        }

        return (queued_funds, payee);

    }

}
