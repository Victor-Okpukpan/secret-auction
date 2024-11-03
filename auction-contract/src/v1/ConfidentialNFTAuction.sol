// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@poseidon-solidity/contracts/PoseidonT3.sol";
import {Verifier} from "./verifier.sol"; // Ensure the correct name

contract ConfidentialNFTAuction is Verifier {
    using ECDSA for bytes32;

    struct Bid {
        address bidder;
        bytes32 commitment; // Poseidon hash commitment
        bool revealed;
        uint256 bidAmount;  // Revealed later
    }

    address public nftSeller;
    IERC721 public nftContract;
    uint256 public nftTokenId;
    bool public auctionActive;
    
    mapping(address => Bid) public bids;
    address public highestBidder;
    uint256 public highestBid;

    constructor(address _nftContract, uint256 _nftTokenId) {
        nftSeller = msg.sender;
        nftContract = IERC721(_nftContract);
        nftTokenId = _nftTokenId;
        auctionActive = true;
    }

    // Function to commit a bid using the commitment (ZKP)    
    function commitBid(uint256 _bidAmount, uint256 _secret) external payable {
        require(auctionActive, "Auction is not active");
        require(bids[msg.sender].bidder == address(0), "Bid already placed");

        uint256 commitment = PoseidonT3.hash([_bidAmount, _secret]);

         bids[msg.sender] = Bid({
            bidder: msg.sender,
            commitment: bytes32(commitment),
            revealed: false,
            bidAmount: 0 
        });
    }

    // Function to reveal a bid after the auction ends
    function revealBid(
        uint256 _bidAmount,
        uint256 _secret,
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[1] calldata _publicSignals
    ) external {
        require(!auctionActive, "Auction is still active");
        Bid storage bid = bids[msg.sender];
        require(bid.bidder == msg.sender, "No bid found");
        require(!bid.revealed, "Bid already revealed");

        // Verify the proof using ZKP Verifier
        require(verifyProof(pA, pB, pC, _publicSignals), "Invalid proof");

        // Ensure the public input matches the commitment
        uint256 computedCommitment = PoseidonT3.hash([_bidAmount, _secret]);
        // bytes32 computedCommitment = keccak256(abi.encodePacked(_bidAmount, _secret));
        require(bytes32(computedCommitment) == bid.commitment, "Commitment mismatch");

        bid.revealed = true;
        bid.bidAmount = _bidAmount;

        // Check if this is the highest bid
        if (_bidAmount > highestBid) {
            highestBid = _bidAmount;
            highestBidder = msg.sender;
        }
    }

    // Function to end the auction and transfer the NFT to the highest bidder
    function endAuction() external {
        require(auctionActive, "Auction already ended");
        require(msg.sender == nftSeller, "Only the seller can end the auction");

        auctionActive = false;

        // Transfer NFT to the highest bidder
        nftContract.transferFrom(nftSeller, highestBidder, nftTokenId);
    }

    // (Optional) Function to withdraw funds for the seller
    function withdraw() external {
        require(!auctionActive, "Auction is still active");
        require(msg.sender == nftSeller, "Only the seller can withdraw");

        payable(nftSeller).transfer(highestBid);
    }
}
