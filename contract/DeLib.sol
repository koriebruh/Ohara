// SPDX-License-Identifier: MIT
pragma solidity >=0.8.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract DeLib is ERC20, Ownable, ReentrancyGuard {
    // Library Structures
    struct Book {
        string title;
        string author;
        string ipfsHash;
        address uploader;
        uint256 timestamp;
        uint256 rankSum;
        uint256 rankCount;
        bool isActive;
    }

    struct Report {
        uint256 bookId;
        address reporter;
        string reason;
        uint256 votes;
        bool resolved;
    }

    struct Review {
        uint256 bookId;
        address reviewer;
        string comment;
        uint8 rating;
    }

    // Token Economics
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000_000 * 10**18; // 1 trillion tokens
    uint256 public constant MAX_WALLET_PERCENTAGE = 2; // 2% max wallet
    uint256 public constant MAX_TX_PERCENTAGE = 1; // 1% max transaction

    uint256 public taxFee = 3; // 3% redistribution
    uint256 public liquidityFee = 2; // 2% to liquidity
    uint256 public uploadRewardFee = 2; // 2% to book uploaders
    uint256 public reviewRewardFee = 1; // 1% to reviewers

    uint256 public immutable maxWalletAmount;
    uint256 public immutable maxTransactionAmount;

    // Reward Settings
    uint256 public constant UPLOAD_REWARD = 1000 * 10**18; // 1000 tokens for upload
    uint256 public constant REVIEW_REWARD = 100 * 10**18; // 100 tokens for review
    uint256 public constant REPORT_REWARD = 50 * 10**18; // 50 tokens for valid report

    // Mappings
    mapping(uint256 => Book) public books;
    mapping(uint256 => Report) public reports;
    mapping(uint256 => Review[]) public bookReviews;
    mapping(address => bool) public blacklist;
    mapping(uint256 => mapping(address => bool)) public hasVotedReport;
    mapping(uint256 => mapping(address => bool)) public hasReviewed;
    mapping(address => bool) public isExcludedFromLimits;
    mapping(address => bool) public isExcludedFromFees;

    // Counters
    uint256 public bookCount;
    uint256 public reportCount;
    uint256 public constant REPORT_THRESHOLD = 5;

    // Events
    event BookUploaded(uint256 indexed bookId, string title, string ipfsHash, address indexed uploader);
    event BookRemoved(uint256 indexed bookId, string reason);
    event Donated(address indexed donor, address indexed uploader, uint256 amount);
    event ReportSubmitted(uint256 indexed reportId, uint256 indexed bookId, address indexed reporter, string reason);
    event ReportVoted(uint256 indexed reportId, address indexed voter, uint256 totalVotes);
    event BookReviewed(uint256 indexed bookId, address indexed reviewer, uint8 rating, string comment);
    event RewardDistributed(address indexed user, uint256 amount, string reason);

    constructor() ERC20("Ohara", "OH") Ownable(msg.sender) {
        maxWalletAmount = (TOTAL_SUPPLY * MAX_WALLET_PERCENTAGE) / 100;
        maxTransactionAmount = (TOTAL_SUPPLY * MAX_TX_PERCENTAGE) / 100;

        // Mint initial supply
        _mint(msg.sender, TOTAL_SUPPLY);

        // Exclude owner and contract from limits and fees
        isExcludedFromLimits[msg.sender] = true;
        isExcludedFromLimits[address(this)] = true;
        isExcludedFromFees[msg.sender] = true;
        isExcludedFromFees[address(this)] = true;
    }

    // Modifiers
    modifier notBlacklisted() {
        require(!blacklist[msg.sender], "You are blacklisted");
        _;
    }

    modifier validBookId(uint256 _bookId) {
        require(_bookId > 0 && _bookId <= bookCount, "Invalid book ID");
        _;
    }

    modifier activeBook(uint256 _bookId) {
        require(books[_bookId].isActive, "Book is not active");
        _;
    }

    // Token Management Functions
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if (from != address(0) && to != address(0)) {
            require(!blacklist[from] && !blacklist[to], "Blacklisted address");

            // Check transaction and wallet limits
            if (!isExcludedFromLimits[from] && !isExcludedFromLimits[to]) {
                require(amount <= maxTransactionAmount, "Transfer exceeds max transaction");
                require(balanceOf(to) + amount <= maxWalletAmount, "Recipient exceeds max wallet");
            }

            // Calculate fees if not excluded
            if (!isExcludedFromFees[from] && !isExcludedFromFees[to]) {
                uint256 taxAmount = (amount * taxFee) / 100;
                uint256 liquidityAmount = (amount * liquidityFee) / 100;
                uint256 uploadRewardAmount = (amount * uploadRewardFee) / 100;
                uint256 reviewRewardAmount = (amount * reviewRewardFee) / 100;
                uint256 totalFee = taxAmount + liquidityAmount + uploadRewardAmount + reviewRewardAmount;

                if (totalFee > 0) {
                    super._update(from, address(this), totalFee);
                    amount -= totalFee;
                }
            }
        }

        super._update(from, to, amount);
    }

    // Library Functions
    function uploadBook(
        string memory _title,
        string memory _author,
        string memory _ipfsHash
    ) public notBlacklisted nonReentrant {
        require(bytes(_title).length > 0, "Title cannot be empty");
        require(bytes(_author).length > 0, "Author cannot be empty");
        require(bytes(_ipfsHash).length > 0, "IPFS hash cannot be empty");

        bookCount++;
        books[bookCount] = Book(
            _title,
            _author,
            _ipfsHash,
            msg.sender,
            block.timestamp,
            0,
            0,
            true
        );

        // Reward uploader
        _distributeReward(msg.sender, UPLOAD_REWARD, "Book Upload");
        emit BookUploaded(bookCount, _title, _ipfsHash, msg.sender);
    }

    function reviewBook(uint256 _bookId, uint8 _rating, string memory _comment)
    public
    notBlacklisted
    validBookId(_bookId)
    activeBook(_bookId)
    nonReentrant
    {
        require(!hasReviewed[_bookId][msg.sender], "Already reviewed this book");
        require(_rating >= 1 && _rating <= 5, "Rating must be between 1 and 5");
        require(bytes(_comment).length > 0, "Comment cannot be empty");

        books[_bookId].rankSum += _rating;
        books[_bookId].rankCount++;
        bookReviews[_bookId].push(Review(_bookId, msg.sender, _comment, _rating));
        hasReviewed[_bookId][msg.sender] = true;

        // Reward reviewer
        _distributeReward(msg.sender, REVIEW_REWARD, "Book Review");
        emit BookReviewed(_bookId, msg.sender, _rating, _comment);
    }

    function reportBook(uint256 _bookId, string memory _reason)
    public
    notBlacklisted
    validBookId(_bookId)
    activeBook(_bookId)
    nonReentrant
    {
        require(bytes(_reason).length > 0, "Reason cannot be empty");

        reportCount++;
        reports[reportCount] = Report(_bookId, msg.sender, _reason, 0, false);

        emit ReportSubmitted(reportCount, _bookId, msg.sender, _reason);
    }

    function voteOnReport(uint256 _reportId) public notBlacklisted nonReentrant {
        require(_reportId > 0 && _reportId <= reportCount, "Invalid report ID");
        require(!hasVotedReport[_reportId][msg.sender], "Already voted on this report");
        require(!reports[_reportId].resolved, "Report already resolved");

        Report storage report = reports[_reportId];
        report.votes++;
        hasVotedReport[_reportId][msg.sender] = true;

        if (report.votes >= REPORT_THRESHOLD) {
            books[report.bookId].isActive = false;
            report.resolved = true;
            // Reward reporter for valid report
            _distributeReward(report.reporter, REPORT_REWARD, "Valid Report");
            emit BookRemoved(report.bookId, report.reason);
        }

        emit ReportVoted(_reportId, msg.sender, report.votes);
    }

    // Internal Functions
    function _distributeReward(address user, uint256 amount, string memory reason) internal {
        if (balanceOf(address(this)) >= amount) {
            _transfer(address(this), user, amount);
            emit RewardDistributed(user, amount, reason);
        }
    }

    // Admin Functions
    function setFees(
        uint256 _taxFee,
        uint256 _liquidityFee,
        uint256 _uploadRewardFee,
        uint256 _reviewRewardFee
    ) external onlyOwner {
        require(_taxFee + _liquidityFee + _uploadRewardFee + _reviewRewardFee <= 10, "Total fee exceeds 10%");
        taxFee = _taxFee;
        liquidityFee = _liquidityFee;
        uploadRewardFee = _uploadRewardFee;
        reviewRewardFee = _reviewRewardFee;
    }

    function setExcludedFromLimits(address account, bool excluded) external onlyOwner {
        isExcludedFromLimits[account] = excluded;
    }

    function setExcludedFromFees(address account, bool excluded) external onlyOwner {
        isExcludedFromFees[account] = excluded;
    }

    function addToBlacklist(address _user) public onlyOwner {
        require(_user != address(0), "Invalid address");
        blacklist[_user] = true;
    }

    // View Functions
    function getBook(uint256 _bookId)
    public
    view
    validBookId(_bookId)
    returns (
        string memory title,
        string memory author,
        string memory ipfsHash,
        address uploader,
        uint256 timestamp,
        uint256 rank,
        bool isActive
    )
    {
        Book memory book = books[_bookId];
        uint256 calculatedRank = book.rankCount > 0 ? book.rankSum / book.rankCount : 0;

        return (
            book.title,
            book.author,
            book.ipfsHash,
            book.uploader,
            book.timestamp,
            calculatedRank,
            book.isActive
        );
    }
}