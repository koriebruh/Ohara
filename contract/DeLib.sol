// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

contract DeLib {

    struct Book {
        string title;
        string author;
        string ipfsHash;
        address uploader;
        uint256 timestamp;
    }

    struct Report {
        uint256 bookId;
        address reporter;
        string reason;
        uint256 vote;
    }

    mapping(uint256 => Book) public books;
    mapping(uint256 => Report) public reports;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    uint256 public bookCount;
    uint256 public reportCount;

    event BookUploaded(uint256 bookId, string title, string ipfsHash, address uploader);
    event Donated(address donor, address uploader, uint256 amount);
    event ReportSubmitted(uint256 reportId, uint256 bookId, address reporter, string reason);
    event ReportVoted(uint256 reportId, address voter, uint256 totalVotes);

    // Upload a book
    function uploadBook(
        string memory _title,
        string memory _author,
        string memory _description,
        string memory _ipfsHash
    ) public {
        bookCount++;
        books[bookCount] = Book(
            _title,
            _author,
            _description,
            _ipfsHash,
            msg.sender,
            block.timestamp
        );

        emit BookUploaded(bookCount, _title, _ipfsHash, msg.sender);
    }

    // Donate to an uploader
    function donate(address _uploader) public payable {
        require(msg.value > 0, "Donation amount must be greater than zero");
        payable(_uploader).transfer(msg.value);
        emit Donated(msg.sender, _uploader, msg.value);
    }

    // Report a book for inappropriate content
    function reportBook(uint256 _bookId, string memory _reason) public {
        require(_bookId > 0 && _bookId <= bookCount, "Invalid book ID");

        reportCount++;
        reports[reportCount] = Report({
            bookId: _bookId,
            reporter: msg.sender,
            reason: _reason,
            votes: 0
        });

        emit ReportSubmitted(reportCount, _bookId, msg.sender, _reason);
    }

    // Vote on a report
    function voteOnReport(uint256 _reportId) public {
        require(_reportId > 0 && _reportId <= reportCount, "Invalid report ID");
        require(!hasVoted[_reportId][msg.sender], "You have already voted on this report");

        reports[_reportId].votes++;
        hasVoted[_reportId][msg.sender] = true;

        emit ReportVoted(_reportId, msg.sender, reports[_reportId].votes);
    }

    // Get book details
    function getBook(uint256 _bookId)
    public
    view
    returns (
        string memory title,
        string memory author,
        string memory description,
        string memory ipfsHash,
        address uploader,
        uint256 timestamp
    )
    {
        require(_bookId > 0 && _bookId <= bookCount, "Invalid book ID");
        Book memory book = books[_bookId];
        return (
            book.title,
            book.author,
            book.description,
            book.ipfsHash,
            book.uploader,
            book.timestamp
        );
    }

}
