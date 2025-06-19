// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract FreelanceMarketplace {
    
    // Struct to represent a job posting
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
    }
    
    // Enum for job status
    enum JobStatus {
        Open,
        InProgress,
        Completed,
        Disputed,
        Cancelled
    }
    
    // State variables
    uint256 private jobCounter;
    mapping(uint256 => Job) public jobs;
    mapping(address => uint256[]) public clientJobs;
    mapping(address => uint256[]) public freelancerJobs;
    mapping(uint256 => uint256) public escrowFunds;
    
    // Events
    event JobPosted(uint256 indexed jobId, address indexed client, string title, uint256 budget);
    event JobAccepted(uint256 indexed jobId, address indexed freelancer);
    event JobCompleted(uint256 indexed jobId);
    event PaymentReleased(uint256 indexed jobId, address indexed freelancer, uint256 amount);
    event JobCancelled(uint256 indexed jobId);
    
    // Modifiers
    modifier onlyClient(uint256 _jobId) {
        require(jobs[_jobId].client == msg.sender, "Only client can perform this action");
        _;
    }
    
    modifier onlyFreelancer(uint256 _jobId) {
        require(jobs[_jobId].freelancer == msg.sender, "Only assigned freelancer can perform this action");
        _;
    }
    
    modifier jobExists(uint256 _jobId) {
        require(_jobId > 0 && _jobId <= jobCounter, "Job does not exist");
        _;
    }
    
    /**
     * @dev Core Function 1: Post a new job
     * @param _title Job title
     * @param _description Job description
     * @param _deadline Job deadline (timestamp)
     */
    function postJob(
        string memory _title,
        string memory _description,
        uint256 _deadline
    ) external payable {
        require(msg.value > 0, "Budget must be greater than 0");
        require(_deadline > block.timestamp, "Deadline must be in the future");
        require(bytes(_title).length > 0, "Title cannot be empty");
        
        jobCounter++;
        
        jobs[jobCounter] = Job({
            jobId: jobCounter,
            client: msg.sender,
            freelancer: address(0),
            title: _title,
            description: _description,
            budget: msg.value,
            deadline: _deadline,
            status: JobStatus.Open,
            isCompleted: false,
            isPaid: false
        });
        
        clientJobs[msg.sender].push(jobCounter);
        escrowFunds[jobCounter] = msg.value;
        
        emit JobPosted(jobCounter, msg.sender, _title, msg.value);
    }
    
    /**
     * @dev Core Function 2: Accept a job (freelancer applies and gets accepted)
     * @param _jobId Job ID to accept
     */
    function acceptJob(uint256 _jobId) external jobExists(_jobId) {
        Job storage job = jobs[_jobId];
        
        require(job.status == JobStatus.Open, "Job is not available");
        require(job.client != msg.sender, "Client cannot accept their own job");
        require(block.timestamp < job.deadline, "Job deadline has passed");
        
        job.freelancer = msg.sender;
        job.status = JobStatus.InProgress;
        
        freelancerJobs[msg.sender].push(_jobId);
        
        emit JobAccepted(_jobId, msg.sender);
    }
    
    /**
     * @dev Core Function 3: Complete job and release payment
     * @param _jobId Job ID to complete
     */
    function completeJobAndPay(uint256 _jobId) external onlyClient(_jobId) jobExists(_jobId) {
        Job storage job = jobs[_jobId];
        
        require(job.status == JobStatus.InProgress, "Job is not in progress");
        require(job.freelancer != address(0), "No freelancer assigned");
        require(!job.isPaid, "Payment already released");
        
        job.status = JobStatus.Completed;
        job.isCompleted = true;
        job.isPaid = true;
        
        uint256 payment = escrowFunds[_jobId];
        escrowFunds[_jobId] = 0;
        
        // Transfer payment to freelancer
        payable(job.freelancer).transfer(payment);
        
        emit JobCompleted(_jobId);
        emit PaymentReleased(_jobId, job.freelancer, payment);
    }
    
    // Additional utility functions
    
    /**
     * @dev Get job details
     * @param _jobId Job ID
     */
    function getJob(uint256 _jobId) external view jobExists(_jobId) returns (Job memory) {
        return jobs[_jobId];
    }
    
    /**
     * @dev Get all jobs posted by a client
     * @param _client Client address
     */
    function getClientJobs(address _client) external view returns (uint256[] memory) {
        return clientJobs[_client];
    }
    
    /**
     * @dev Get all jobs accepted by a freelancer
     * @param _freelancer Freelancer address
     */
    function getFreelancerJobs(address _freelancer) external view returns (uint256[] memory) {
        return freelancerJobs[_freelancer];
    }
    
    /**
     * @dev Cancel a job (only if not started or in dispute)
     * @param _jobId Job ID to cancel
     */
    function cancelJob(uint256 _jobId) external onlyClient(_jobId) jobExists(_jobId) {
        Job storage job = jobs[_jobId];
        
        require(job.status == JobStatus.Open || job.status == JobStatus.Disputed, "Cannot cancel job in current status");
        require(!job.isPaid, "Cannot cancel paid job");
        
        job.status = JobStatus.Cancelled;
        
        // Refund the client
        uint256 refund = escrowFunds[_jobId];
        escrowFunds[_jobId] = 0;
        payable(job.client).transfer(refund);
        
        emit JobCancelled(_jobId);
    }
    
    /**
     * @dev Get total number of jobs posted
     */
    function getTotalJobs() external view returns (uint256) {
        return jobCounter;
    }
    
    /**
     * @dev Get contract balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
