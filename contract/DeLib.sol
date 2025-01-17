// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

contract DeLib {
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
    }

    struct Review {
        uint256 bookId;
        address reviewer;
        string comment;
        uint8 rating; // 1-5 stars
    }

    mapping(uint256 => Book) public books;
    mapping(uint256 => Report) public reports;
    mapping(uint256 => Review[]) public bookReviews;
    mapping(address => bool) public blacklist;
    mapping(uint256 => mapping(address => bool)) public hasVotedReport;
    mapping(uint256 => mapping(address => bool)) public hasReviewed;

    uint256 public bookCount;
    uint256 public reportCount;

    event BookUploaded(uint256 bookId, string title, string ipfsHash, address uploader);
    event BookRemoved(uint256 bookId, string reason);
    event Donated(address donor, address uploader, uint256 amount);
    event ReportSubmitted(uint256 reportId, uint256 bookId, address reporter, string reason);
    event ReportVoted(uint256 reportId, address voter, uint256 totalVotes);
    event BookReviewed(uint256 bookId, address reviewer, uint8 rating, string comment);

    modifier notBlacklisted() {
        require(!blacklist[msg.sender], "You are blacklisted");
        _;
    }

    // Upload a book
    function uploadBook(
        string memory _title,
        string memory _author,
        string memory _ipfsHash
    ) public notBlacklisted {
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
        emit BookUploaded(bookCount, _title, _ipfsHash, msg.sender);
    }

    // Donate to an uploader
    function donate(address _uploader) public payable notBlacklisted {
        require(msg.value > 0, "Donation amount must be greater than zero");
        payable(_uploader).transfer(msg.value);
        emit Donated(msg.sender, _uploader, msg.value);
    }

    // Report a book
    function reportBook(uint256 _bookId, string memory _reason) public notBlacklisted {
        require(_bookId > 0 && _bookId <= bookCount, "Invalid book ID");
        require(books[_bookId].isActive, "Book is already removed");

        reportCount++;
        reports[reportCount] = Report(_bookId, msg.sender, _reason, 0);
        emit ReportSubmitted(reportCount, _bookId, msg.sender, _reason);
    }

    // Vote on a report
    function voteOnReport(uint256 _reportId) public notBlacklisted {
        require(_reportId > 0 && _reportId <= reportCount, "Invalid report ID");
        require(!hasVotedReport[_reportId][msg.sender], "You have already voted on this report");

        reports[_reportId].votes++;
        hasVotedReport[_reportId][msg.sender] = true;

        // If votes exceed threshold, deactivate the book
        if (reports[_reportId].votes >= 5) {
            uint256 bookId = reports[_reportId].bookId;
            books[bookId].isActive = false;
            emit BookRemoved(bookId, reports[_reportId].reason);
        }

        emit ReportVoted(_reportId, msg.sender, reports[_reportId].votes);
    }

    // Review a book
    function reviewBook(uint256 _bookId, uint8 _rating, string memory _comment) public notBlacklisted {
        require(_bookId > 0 && _bookId <= bookCount, "Invalid book ID");
        require(books[_bookId].isActive, "Book is not active");
        require(!hasReviewed[_bookId][msg.sender], "You have already reviewed this book");
        require(_rating >= 1 && _rating <= 5, "Rating must be between 1 and 5");

        books[_bookId].rankSum += _rating;
        books[_bookId].rankCount++;

        bookReviews[_bookId].push(Review(_bookId, msg.sender, _comment, _rating));
        hasReviewed[_bookId][msg.sender] = true;

        emit BookReviewed(_bookId, msg.sender, _rating, _comment);
    }

    // Get book details
    function getBook(uint256 _bookId)
    public
    view
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
        require(_bookId > 0 && _bookId <= bookCount, "Invalid book ID");

        Book memory book = books[_bookId];
        rank = book.rankCount > 0 ? book.rankSum / book.rankCount : 0;  // Gunakan rank yang sudah dideklarasikan pada parameter

        return (
            book.title,
            book.author,
            book.ipfsHash,
            book.uploader,
            book.timestamp,
            rank,
            book.isActive
        );
    }


    // Blacklist a user
    function addToBlacklist(address _user) public {
        require(msg.sender == address(this), "Only contract can blacklist");
        blacklist[_user] = true;
    }
}
