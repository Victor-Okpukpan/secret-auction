// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "../AbstractCallback.sol";

contract NFTAuction is
    ReentrancyGuard,
    AutomationCompatibleInterface,
    AbstractCallback
{
    // New event to be emitted at the end of the auction
    event AuctionEndedReactive(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed highestBidder,
        address nftContract,
        uint256 nftTokenId,
        uint256 highestBidAmount,
        address[] allBidders,
        uint256[] allBidAmounts
    );

    struct Auction {
        address seller;
        uint256 startTime;
        uint256 endTime;
        uint256 nftTokenId;
        IERC721 nftContract;
        bool isActive;
        Bid highestBid;
    }

    struct Bid {
        address bidder;
        uint256 amount;
        uint256 timestamp;
    }

    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => Bid[]) public bids;
    uint256 public auctionCount;
    uint256 public minBidIncrement = 0.01 ether;

    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed seller,
        address nftContract,
        uint256 nftTokenId,
        uint256 endTime
    );
    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount
    );
    event AuctionEnded(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 amount
    );

    modifier onlyActiveAuction(uint256 _auctionId) {
        require(auctions[_auctionId].isActive, "Auction is not active");
        _;
    }

    constructor(
        address _callback_sender
    ) payable AbstractCallback(_callback_sender) {
        auctionCount = 0;
    }

    function createAuction(
        address _nftContract,
        uint256 _nftTokenId,
        uint256 _duration
    ) external nonReentrant {
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
            startTime: block.timestamp,
            endTime: block.timestamp + _duration,
            nftTokenId: _nftTokenId,
            nftContract: nftContract,
            isActive: true,
            highestBid: Bid({bidder: address(0), amount: 0, timestamp: 0})
        });

        auctionCount++;
        emit AuctionCreated(
            auctionId,
            msg.sender,
            _nftContract,
            _nftTokenId,
            auctions[auctionId].endTime
        );
    }

    function placeBid(
        uint256 _auctionId
    ) external payable nonReentrant onlyActiveAuction(_auctionId) {
        Auction storage auction = auctions[_auctionId];
        require(block.timestamp < auction.endTime, "Auction has ended");
        require(msg.value >= minBidIncrement, "Bid amount too low");

        bids[_auctionId].push(
            Bid({
                bidder: msg.sender,
                amount: msg.value,
                timestamp: block.timestamp
            })
        );

        emit BidPlaced(_auctionId, msg.sender, msg.value);
    }

    // Modified endAuction function
    function endAuction(
        uint256 _auctionId
    ) public nonReentrant onlyActiveAuction(_auctionId) {
        Auction storage auction = auctions[_auctionId];
        require(block.timestamp >= auction.endTime, "Auction is still ongoing");

        auction.isActive = false;
        Bid[] storage auctionBids = bids[_auctionId];

        address[] memory allBidders = new address[](auctionBids.length);
        uint256[] memory allBidAmounts = new uint256[](auctionBids.length);

        for (uint256 i = 0; i < auctionBids.length; i++) {
            allBidders[i] = auctionBids[i].bidder;
            allBidAmounts[i] = auctionBids[i].amount;
        }

        if (auctionBids.length > 0) {
            Bid memory highestBid = auctionBids[0];
            for (uint256 i = 1; i < auctionBids.length; i++) {
                if (
                    auctionBids[i].amount > highestBid.amount ||
                    (auctionBids[i].amount == highestBid.amount &&
                        auctionBids[i].timestamp < highestBid.timestamp)
                ) {
                    highestBid = auctionBids[i];
                }
            }

            emit AuctionEndedReactive(
                _auctionId,
                auction.seller,
                address(auction.nftContract),
                auction.nftTokenId,
                highestBid.bidder,
                highestBid.amount,
                allBidders,
                allBidAmounts
            );
        } else {
            auction.nftContract.transferFrom(
                address(this),
                auction.seller,
                auction.nftTokenId
            );
        }
    }

    receive() external payable {}

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
}
