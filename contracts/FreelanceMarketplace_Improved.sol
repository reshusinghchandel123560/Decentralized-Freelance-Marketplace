// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title FreelanceMarketplace
 * @dev A secure, decentralized freelance marketplace with escrow protection
 * @notice This contract handles job postings, freelancer assignments, and automated payments
 */
contract FreelanceMarketplace {
    
    // ==================== Structs ====================
    
    /// @dev Represents a job posting on the platform
    struct Job {
        uint256 jobId;
        address client;
        address freelancer;
        string title;
        string description;
        uint256 budget;
        uint256 deadline;
        JobStatus status;
        bool isCompleted;
        bool isPaid;
        uint256 createdAt;
    }
    
    // ==================== Enums ====================
    
    /// @dev Represents the lifecycle status of a job
    enum JobStatus {
        Open,           // 0: Available for freelancers to accept
        InProgress,     // 1: Assigned to a freelancer
        Completed,      // 2: Work finished, awaiting payment
        Disputed,       // 3: Under dispute resolution
        Cancelled       // 4: Job cancelled, funds refunded
    }
    
    // ==================== State Variables ====================
    
    address private owner;
    uint256 private jobCounter;
    uint256 private constant MAX_DESCRIPTION_LENGTH = 5000;
    uint256 private constant MAX_TITLE_LENGTH = 200;
    uint256 private constant MIN_DEADLINE_BUFFER = 1 hours;
    
    mapping(uint256 => Job) public jobs;
    mapping(address => uint256[]) public clientJobs;
    mapping(address => uint256[]) public freelancerJobs;
    mapping(uint256 => uint256) public escrowFunds;
    mapping(address => bool) public registeredClients;
    mapping(uint256 => address) public jobDisputeInitiator;
    mapping(uint256 => uint256) public jobDisputedAt;
    
    // ==================== Events ====================
    
    /// @notice Emitted when a new job is posted
    event JobPosted(
        uint256 indexed jobId,
        address indexed client,
        string title,
        uint256 budget,
        uint256 deadline,
        uint256 timestamp
    );
    
    /// @notice Emitted when a freelancer accepts a job
    event JobAccepted(
        uint256 indexed jobId,
        address indexed freelancer,
        uint256 timestamp
    );
    
    /// @notice Emitted when a job is marked as completed
    event JobCompleted(
        uint256 indexed jobId,
        uint256 timestamp
    );
    
    /// @notice Emitted when payment is released to a freelancer
    event PaymentReleased(
        uint256 indexed jobId,
        address indexed freelancer,
        uint256 amount,
        uint256 timestamp
    );
    
    /// @notice Emitted when a job is cancelled
    event JobCancelled(
        uint256 indexed jobId,
        uint256 refundAmount,
        uint256 timestamp
    );
    
    /// @notice Emitted when a dispute is raised
    event DisputeRaised(
        uint256 indexed jobId,
        address indexed initiator,
        uint256 timestamp
    );
    
    /// @notice Emitted when a dispute is resolved
    event DisputeResolved(
        uint256 indexed jobId,
        address indexed winner,
        uint256 amount,
        uint256 timestamp
    );
    
    // ==================== Modifiers ====================
    
    /// @dev Ensures only the contract owner can call the function
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }
    
    /// @dev Ensures only the job client can call the function
    modifier onlyClient(uint256 _jobId) {
        require(jobs[_jobId].client == msg.sender, "Only client can perform this action");
        _;
    }
    
    /// @dev Ensures only the assigned freelancer can call the function
    modifier onlyFreelancer(uint256 _jobId) {
        require(jobs[_jobId].freelancer == msg.sender, "Only assigned freelancer can perform this action");
        _;
    }
    
    /// @dev Ensures the job exists and is valid
    modifier jobExists(uint256 _jobId) {
        require(_jobId > 0 && _jobId <= jobCounter, "Job does not exist");
        _;
    }
    
    /// @dev Ensures the caller is registered as a client
    modifier onlyRegisteredClient() {
        require(registeredClients[msg.sender], "Not registered as a client");
        _;
    }
    
    // ==================== Constructor ====================
    
    constructor() {
        owner = msg.sender;
    }
    
    // ==================== Core Functions ====================
    
    /**
     * @notice Register as a client on the platform
     * @dev Required before posting jobs
     */
    function registerAsClient() external {
        registeredClients[msg.sender] = true;
    }
    
    /**
     * @notice Post a new freelance job with escrow protection
     * @param _title The title of the job
     * @param _description Detailed description of the job requirements
     * @param _deadline Unix timestamp when the job should be completed
     * @return jobId The ID of the newly created job
     * 
     * Requirements:
     * - Budget must be greater than 0 (sent as msg.value)
     * - Deadline must be in the future
     * - Title cannot be empty or exceed max length
     * - Description cannot be empty or exceed max length
     * - Caller must be registered as a client
     */
    function postJob(
        string memory _title,
        string memory _description,
        uint256 _deadline
    ) external payable onlyRegisteredClient returns (uint256) {
        // Input validation
        require(msg.value > 0, "Budget must be greater than 0");
        require(_deadline > block.timestamp + MIN_DEADLINE_BUFFER, "Deadline must be at least 1 hour in the future");
        require(bytes(_title).length > 0, "Title cannot be empty");
        require(bytes(_title).length <= MAX_TITLE_LENGTH, "Title exceeds maximum length");
        require(bytes(_description).length > 0, "Description cannot be empty");
        require(bytes(_description).length <= MAX_DESCRIPTION_LENGTH, "Description exceeds maximum length");
        
        // Increment job counter and create new job
        jobCounter++;
        uint256 newJobId = jobCounter;
        
        jobs[newJobId] = Job({
            jobId: newJobId,
            client: msg.sender,
            freelancer: address(0),
            title: _title,
            description: _description,
            budget: msg.value,
            deadline: _deadline,
            status: JobStatus.Open,
            isCompleted: false,
            isPaid: false,
            createdAt: block.timestamp
        });
        
        clientJobs[msg.sender].push(newJobId);
        escrowFunds[newJobId] = msg.value;
        
        emit JobPosted(newJobId, msg.sender, _title, msg.value, _deadline, block.timestamp);
        
        return newJobId;
    }
    
    /**
     * @notice Accept a job as a freelancer
     * @param _jobId The ID of the job to accept
     * 
     * Requirements:
     * - Job must exist and be open
     * - Caller cannot be the job client
     * - Deadline must not have passed
     */
    function acceptJob(uint256 _jobId) external jobExists(_jobId) {
        Job storage job = jobs[_jobId];
        
        require(job.status == JobStatus.Open, "Job is not available");
        require(job.client != msg.sender, "Client cannot accept their own job");
        require(block.timestamp < job.deadline, "Job deadline has passed");
        
        job.freelancer = msg.sender;
        job.status = JobStatus.InProgress;
        
        freelancerJobs[msg.sender].push(_jobId);
        
        emit JobAccepted(_jobId, msg.sender, block.timestamp);
    }
    
    /**
     * @notice Complete a job and release payment to the freelancer
     * @param _jobId The ID of the job to complete
     * 
     * Requirements:
     * - Only the client can call this function
     * - Job must be in progress
     * - Payment must not have been released yet
     * 
     * Security:
     * - Uses Checks-Effects-Interactions pattern
     * - State updated before external call
     * - Uses low-level call instead of transfer
     */
    function completeJobAndPay(uint256 _jobId) external onlyClient(_jobId) jobExists(_jobId) {
        Job storage job = jobs[_jobId];
        
        // Checks
        require(job.status == JobStatus.InProgress, "Job is not in progress");
        require(job.freelancer != address(0), "No freelancer assigned");
        require(!job.isPaid, "Payment already released");
        
        // Effects - Update state BEFORE external call
        job.status = JobStatus.Completed;
        job.isCompleted = true;
        job.isPaid = true;
        
        uint256 payment = escrowFunds[_jobId];
        escrowFunds[_jobId] = 0;
        
        // Interactions - External call at the end
        (bool success, ) = payable(job.freelancer).call{value: payment}("");
        require(success, "Payment transfer failed");
        
        emit JobCompleted(_jobId, block.timestamp);
        emit PaymentReleased(_jobId, job.freelancer, payment, block.timestamp);
    }
    
    /**
     * @notice Cancel a job and refund the client
     * @param _jobId The ID of the job to cancel
     * 
     * Requirements:
     * - Only the client can call this function
     * - Job must be open or disputed
     * - Job must not have been paid already
     */
    function cancelJob(uint256 _jobId) external onlyClient(_jobId) jobExists(_jobId) {
        Job storage job = jobs[_jobId];
        
        require(
            job.status == JobStatus.Open || job.status == JobStatus.Disputed,
            "Cannot cancel job in current status"
        );
        require(!job.isPaid, "Cannot cancel paid job");
        
        job.status = JobStatus.Cancelled;
        
        // Update state before transfer
        uint256 refund = escrowFunds[_jobId];
        escrowFunds[_jobId] = 0;
        
        // Transfer refund to client
        (bool success, ) = payable(job.client).call{value: refund}("");
        require(success, "Refund transfer failed");
        
        emit JobCancelled(_jobId, refund, block.timestamp);
    }
    
    // ==================== Dispute Resolution ====================
    
    /**
     * @notice Raise a dispute for a job
     * @param _jobId The ID of the job to dispute
     * 
     * Requirements:
     * - Only client or freelancer can raise a dispute
     * - Job must be in progress or completed
     * - Can only dispute once
     */
    function raiseDispute(uint256 _jobId) external jobExists(_jobId) {
        Job storage job = jobs[_jobId];
        
        require(
            msg.sender == job.client || msg.sender == job.freelancer,
            "Only client or freelancer can raise dispute"
        );
        require(
            job.status == JobStatus.InProgress || job.status == JobStatus.Completed,
            "Cannot dispute job in current status"
        );
        require(jobDisputedAt[_jobId] == 0, "Dispute already raised for this job");
        
        job.status = JobStatus.Disputed;
        jobDisputeInitiator[_jobId] = msg.sender;
        jobDisputedAt[_jobId] = block.timestamp;
        
        emit DisputeRaised(_jobId, msg.sender, block.timestamp);
    }
    
    /**
     * @notice Resolve a dispute (owner only)
     * @param _jobId The ID of the disputed job
     * @param _winner Address of the dispute winner (client or freelancer)
     * 
     * Requirements:
     * - Only owner can resolve disputes
     * - Job must be disputed
     * - Winner must be either client or freelancer
     */
    function resolveDispute(uint256 _jobId, address _winner) 
        external 
        onlyOwner 
        jobExists(_jobId) 
    {
        Job storage job = jobs[_jobId];
        
        require(job.status == JobStatus.Disputed, "Job is not disputed");
        require(
            _winner == job.client || _winner == job.freelancer,
            "Winner must be client or freelancer"
        );
        
        uint256 amount = escrowFunds[_jobId];
        escrowFunds[_jobId] = 0;
        
        job.status = JobStatus.Completed;
        job.isPaid = true;
        
        (bool success, ) = payable(_winner).call{value: amount}("");
        require(success, "Payment transfer failed");
        
        emit DisputeResolved(_jobId, _winner, amount, block.timestamp);
    }
    
    // ==================== View Functions ====================
    
    /**
     * @notice Get detailed information about a job
     * @param _jobId The ID of the job
     * @return Job The job details
     */
    function getJob(uint256 _jobId) external view jobExists(_jobId) returns (Job memory) {
        return jobs[_jobId];
    }
    
    /**
     * @notice Get all job IDs posted by a client
     * @param _client The address of the client
     * @return Array of job IDs
     */
    function getClientJobs(address _client) external view returns (uint256[] memory) {
        return clientJobs[_client];
    }
    
    /**
     * @notice Get all job IDs accepted by a freelancer
     * @param _freelancer The address of the freelancer
     * @return Array of job IDs
     */
    function getFreelancerJobs(address _freelancer) external view returns (uint256[] memory) {
        return freelancerJobs[_freelancer];
    }
    
    /**
     * @notice Get the total number of jobs posted on the platform
     * @return Total job count
     */
    function getTotalJobs() external view returns (uint256) {
        return jobCounter;
    }
    
    /**
     * @notice Get the current balance held in escrow
     * @return Contract balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    /**
     * @notice Check if an address is registered as a client
     * @param _address The address to check
     * @return Boolean indicating registration status
     */
    function isClientRegistered(address _address) external view returns (bool) {
        return registeredClients[_address];
    }
    
    /**
     * @notice Get the escrow funds for a specific job
     * @param _jobId The ID of the job
     * @return The amount of funds held in escrow
     */
    function getEscrowAmount(uint256 _jobId) external view jobExists(_jobId) returns (uint256) {
        return escrowFunds[_jobId];
    }
    
    // ==================== Admin Functions ====================
    
    /**
     * @notice Emergency withdrawal by owner
     * @dev Only for emergency situations
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = payable(owner).call{value: balance}("");
        require(success, "Emergency withdrawal failed");
    }
    
    /**
     * @notice Transfer ownership to a new owner
     * @param _newOwner The address of the new owner
     */
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Invalid new owner address");
        owner = _newOwner;
    }
    
    /**
     * @notice Get the current owner address
     * @return The owner's address
     */
    function getOwner() external view returns (address) {
        return owner;
    }
}
