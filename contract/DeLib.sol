// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

    struct Achievement {
        string name;
        string description;
        bool unlocked;
    }

    // Token Economics
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000_000 * 10**18; // 1 trillion tokens
    uint256 public constant MAX_WALLET_PERCENTAGE = 2; // 2% max wallet
    uint256 public constant MAX_TX_PERCENTAGE = 1; // 1% max transaction

    uint256 public taxFee = 3; // 3% redistribution
    uint256 public liquidityFee = 2; // 2% to liquidity
    uint256 public uploadRewardFee = 2; // 2% to book uploaders
    uint256 public reviewRewardFee = 1; // 1% to reviewers
    uint256 public burnFee = 1; // 1% auto-burn

    uint256 public immutable maxWalletAmount;
    uint256 public immutable maxTransactionAmount;

    // Reward Settings
    uint256 public constant UPLOAD_REWARD = 1000 * 10**18; // 1000 tokens for upload
    uint256 public constant REVIEW_REWARD = 100 * 10**18; // 100 tokens for review
    uint256 public constant REPORT_REWARD = 50 * 10**18; // 50 tokens for valid report

    // State Variables
    bool public isPaused;

    // Mappings
    mapping(uint256 => Book) public books;
    mapping(uint256 => Report) public reports;
    mapping(uint256 => Review[]) public bookReviews;
    mapping(address => bool) public blacklist;
    mapping(uint256 => mapping(address => bool)) public hasVotedReport;
    mapping(uint256 => mapping(address => bool)) public hasReviewed;
    mapping(address => bool) public isExcludedFromLimits;
    mapping(address => bool) public isExcludedFromFees;

    // Social Features
    mapping(address => address[]) public following;
    mapping(address => address[]) public followers;
    mapping(uint256 => mapping(address => bool)) public favoriteBooks;
    mapping(uint256 => uint256) public favoritesCount;
    mapping(address => Achievement[]) public userAchievements;

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
    event AchievementUnlocked(address indexed user, string name);
    event UserFollowed(address indexed follower, address indexed followed);
    event BookFavorited(uint256 indexed bookId, address indexed user, bool status);
    event TokensBurned(address indexed from, uint256 amount);

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

    modifier notPaused() {
        require(!isPaused, "Contract is paused");
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
                uint256 burnAmount = (amount * burnFee) / 100;
                uint256 totalFee = taxAmount + liquidityAmount + uploadRewardAmount + reviewRewardAmount;

                if (totalFee > 0) {
                    super._update(from, address(this), totalFee);
                    amount -= totalFee;
                }

                if (burnAmount > 0) {
                    _burn(from, burnAmount);
                    emit TokensBurned(from, burnAmount);
                    amount -= burnAmount;
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
    ) public notBlacklisted notPaused nonReentrant {
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
        checkAndUpdateAchievements(msg.sender);
        emit BookUploaded(bookCount, _title, _ipfsHash, msg.sender);
    }

    function reviewBook(uint256 _bookId, uint8 _rating, string memory _comment)
    public
    notBlacklisted
    notPaused
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

        // Calculate and distribute reward
        uint256 reward = calculateReviewReward(msg.sender);
        _distributeReward(msg.sender, reward, "Book Review");
        checkAndUpdateAchievements(msg.sender);
        emit BookReviewed(_bookId, msg.sender, _rating, _comment);
    }

    // Social Functions
    function followUser(address _user) external notBlacklisted notPaused {
        require(_user != msg.sender, "Cannot follow yourself");
        require(!blacklist[_user], "User is blacklisted");
        following[msg.sender].push(_user);
        followers[_user].push(msg.sender);
        emit UserFollowed(msg.sender, _user);
    }

    function toggleFavorite(uint256 _bookId) external notBlacklisted validBookId(_bookId) notPaused {
        bool newStatus = !favoriteBooks[_bookId][msg.sender];
        favoriteBooks[_bookId][msg.sender] = newStatus;
        if(newStatus) {
            favoritesCount[_bookId]++;
        } else {
            favoritesCount[_bookId]--;
        }
        emit BookFavorited(_bookId, msg.sender, newStatus);
    }

    // Reward System Functions
    function calculateReviewReward(address _reviewer) internal view returns (uint256) {
        uint256 reviewCount;
        for(uint i = 1; i <= bookCount; i++) {
            if(hasReviewed[i][_reviewer]) reviewCount++;
        }

        // Bonus 10% setiap 10 review
        uint256 bonusMultiplier = (reviewCount / 10) * 10;
        return REVIEW_REWARD + (REVIEW_REWARD * bonusMultiplier / 100);
    }

    function checkAndUpdateAchievements(address _user) internal {
        // First Upload Achievement
        if(getUserUploadCount(_user) == 1) {
            unlockAchievement(_user, "First Upload", "Upload your first book");
        }

        // Prolific Author Achievement
        if(getUserUploadCount(_user) >= 5) {
            unlockAchievement(_user, "Prolific Author", "Upload 5 or more books");
        }

        // Active Reviewer Achievement
        if(getUserReviewCount(_user) >= 10) {
            unlockAchievement(_user, "Active Reviewer", "Write 10 or more reviews");
        }
    }

    function unlockAchievement(address _user, string memory _name, string memory _description) internal {
        if(!hasAchievement(_user, _name)) {
            Achievement memory newAchievement = Achievement(_name, _description, true);
            userAchievements[_user].push(newAchievement);
            _distributeReward(_user, 500 * 10**18, "Achievement Reward");
            emit AchievementUnlocked(_user, _name);
        }
    }

    // Admin Functions
    function setPause(bool _state) external onlyOwner {
        isPaused = _state;
    }

    function removeFromBlacklist(address _user) public onlyOwner {
        blacklist[_user] = false;
    }

    function emergencyWithdraw(address _token) external onlyOwner {
        if(_token == address(0)) {
            payable(owner()).transfer(address(this).balance);
        } else {
            IERC20(_token).transfer(owner(), IERC20(_token).balanceOf(address(this)));
        }
    }

    // View Functions
    function getBookReviews(uint256 _bookId) external view returns (Review[] memory) {
        return bookReviews[_bookId];
    }

    function getPlatformStats() external view returns (
        uint256 totalBooks,
        uint256 totalActiveBooks,
        uint256 totalReports,
        uint256 totalReviews
    ) {
        uint256 activeBooks;
        uint256 reviews;

        for(uint i = 1; i <= bookCount; i++) {
            if(books[i].isActive) activeBooks++;
            reviews += books[i].rankCount;
        }

        return (bookCount, activeBooks, reportCount, reviews);
    }

    function getUserUploadCount(address _user) public view returns (uint256) {
        uint256 count;
        for(uint i = 1; i <= bookCount; i++) {
            if(books[i].uploader == _user) count++;
        }
        return count;
    }

    function getUserReviewCount(address _user) public view returns (uint256) {
        uint256 count;
        for(uint i = 1; i <= bookCount; i++) {
            if(hasReviewed[i][_user]) count++;
        }
        return count;
    }

    function hasAchievement(address _user, string memory _name) public view returns (bool) {
        Achievement[] memory achievements = userAchievements[_user];
        for(uint i = 0; i < achievements.length; i++) {
            if(keccak256(bytes(achievements[i].name)) == keccak256(bytes(_name))) {
                return true;
            }
        }
        return false;
    }

    // Internal Functions
    function _distributeReward(address user, uint256 amount, string memory reason) internal {
        if (balanceOf(address(this)) >= amount) {
            _transfer(address(this), user, amount);
            emit RewardDistributed(user, amount, reason);
        }
    }
}