// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "../AbstractCallback.sol";

contract SecretAuction is
    ReentrancyGuard,
    AutomationCompatibleInterface,
    AbstractCallback {
    struct Bid {
        address bidder;
        uint256 amount;
    }

    struct Auction {
        address seller;
        address nftContract;
        uint256 nftTokenId;
        uint256 endTime;
        uint256 minBid;
        bool isActive;
        Bid[] bids;
    }

    mapping(uint256 => Auction) public auctions;
    uint256 public auctionCount;

    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed nftContract,
        uint256 nftTokenId,
        uint256 endTime,
        uint256 minBid
    );

    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount
    );
    event AuctionEnded(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 highestBid
    );
    event RefundIssued(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount
    );
    event OwnershipTransferred(
        address indexed token,
        uint256 indexed token_id,
        address indexed newOwner
    );

    constructor(
        address _callback_sender
    ) payable AbstractCallback(_callback_sender) {
        auctionCount = 0;
    }

    function createAuction(
        address _nftContract,
        uint256 _nftTokenId,
        uint256 _duration,
        uint256 _minBid
    ) external {
        require(_duration > 0, "Duration must be greater than 0");

        IERC721 nftContract = IERC721(_nftContract);
        require(
            nftContract.ownerOf(_nftTokenId) == msg.sender,
            "Only NFT owner can create auction"
        );
        nftContract.transferFrom(msg.sender, address(this), _nftTokenId);

        uint256 auctionId = auctionCount;
        auctions[auctionId] = Auction({
            seller: msg.sender,
            nftContract: _nftContract,
            nftTokenId: _nftTokenId,
            endTime: block.timestamp + _duration,
            minBid: _minBid,
            isActive: true,
            bids: new Bid[](0)
        });

        auctionCount++;
        emit AuctionCreated(
            auctionId,
            msg.sender,
            _nftContract,
            _nftTokenId,
            auctions[auctionId].endTime,
            _minBid
        );
    }

    function placeBid(uint256 _auctionId) external payable {
        Auction storage auction = auctions[_auctionId];
        require(block.timestamp < auction.endTime, "Auction has ended");
        require(msg.value >= auction.minBid, "Bid amount too low");
        require(auction.isActive, "Auction is not active");

        auction.bids.push(Bid({bidder: msg.sender, amount: msg.value}));
        emit BidPlaced(_auctionId, msg.sender, msg.value);
    }

    function endAuction(uint256 _auctionId) internal {
        Auction storage auction = auctions[_auctionId];
        require(block.timestamp >= auction.endTime, "Auction still ongoing");
        require(auction.isActive, "Auction has already ended");

        auction.isActive = false;

        // Find the highest bid
        uint256 highestBidAmount = 0;
        address highestBidder;

        for (uint256 i = 0; i < auction.bids.length; i++) {
            Bid memory currentBid = auction.bids[i];
            if (currentBid.amount > highestBidAmount) {
                highestBidAmount = currentBid.amount;
                highestBidder = currentBid.bidder;
            }
        }

        // Transfer NFT to the highest bidder and initiate ownership tracking
        if (highestBidAmount > 0) {
            IERC721(auction.nftContract).transferFrom(
                address(this),
                highestBidder,
                auction.nftTokenId
            );
            payable(auction.seller).transfer(highestBidAmount);
            emit AuctionEnded(_auctionId, highestBidder, highestBidAmount);

            // Trigger ownership tracking
            triggerOwnershipTransfer(auction.nftContract, auction.nftTokenId, highestBidder);
        } else {
            // No valid bids; return NFT to seller
            IERC721(auction.nftContract).transferFrom(
                address(this),
                auction.seller,
                auction.nftTokenId
            );
        }

        // Refund all other bidders
        for (uint256 i = 0; i < auction.bids.length; i++) {
            Bid memory currentBid = auction.bids[i];
            if (currentBid.bidder != highestBidder) {
                payable(currentBid.bidder).transfer(currentBid.amount);
                emit RefundIssued(
                    _auctionId,
                    currentBid.bidder,
                    currentBid.amount
                );
            }
        }
    }

    function triggerOwnershipTransfer(
         address _token,
        uint256 _token_id,
        address _newOwner
    ) internal {
        // Logic to trigger the Reactive Network’s ownership tracking.
        // Here we emit an event to simulate the ownership change notification
        // for tracking. This could later be connected to an actual reactive component.

        emit OwnershipTransferred(_token, _token_id, _newOwner);
    }

    function checkUpkeep(
        bytes calldata
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded = false;
        for (uint256 i = 0; i < auctionCount; i++) {
            if (
                auctions[i].isActive && block.timestamp >= auctions[i].endTime
            ) {
                upkeepNeeded = true;
                performData = abi.encode(i); // Pass auction ID to performUpkeep
                break;
            }
        }
    }

    function performUpkeep(bytes calldata performData) external override {
        uint256 auctionId = abi.decode(performData, (uint256));
        if (
            auctions[auctionId].isActive &&
            block.timestamp >= auctions[auctionId].endTime
        ) {
            endAuction(auctionId);
        }
    }

    receive() external payable {}

}
