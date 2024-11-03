// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../IReactive.sol";
import "../AbstractPausableReactive.sol";
import "../ISystemContract.sol";

contract NFTAuctionReactive is IReactive, AbstractPausableReactive {
    struct AuctionInfo {
        address seller;
        address nftContract;
        uint256 nftTokenId;
        uint256 highestBidAmount;
        address highestBidder;
        address[] allBidders;
        uint256[] allBidAmounts;
    }

    mapping(uint256 => AuctionInfo) public auctions;
    uint256 private constant SEPOLIA_CHAIN_ID = 11155111;

    uint256 private constant AUCTION_END_TOPIC_0 =
        0x422f20c2fc60d06e111a83635b24fec3cae3b8cd71e773db5e087c761a8acc54;

    uint64 private constant CALLBACK_GAS_LIMIT = 1000000;

    constructor(address _service, address _contract) {
        owner = msg.sender;
        paused = false;
        service = ISystemContract(payable(_service));
        // Set up the subscription to listen to the auction end event
        bytes memory payload = abi.encodeWithSignature(
            "subscribe(uint256,address,uint256,uint256,uint256,uint256)",
            SEPOLIA_CHAIN_ID,
            _contract,
            AUCTION_END_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        (bool subscriptionResult, ) = address(service).call(payload);
        require(subscriptionResult, "Subscription failed");
    }

    // Receives funds for settlement purposes
    receive() external payable {}

     function getPausableSubscriptions()
        internal
        pure
        override
        returns (Subscription[] memory)
    {
        Subscription[] memory result = new Subscription[](1);
        result[0] = Subscription(
            SEPOLIA_CHAIN_ID,
            address(0),
            AUCTION_END_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        return result;
    }

    function react(
        uint256 chain_id,
        address auctionContract,    
        uint256 topic_0,
        uint256 auctionId,
        uint256 highestBidAmount,
        uint256 /* topic_3 */,
        bytes calldata data,
        uint256 /* block_number */,
        uint256 op_code
    ) external vmOnly {
        require(topic_0 == AUCTION_END_TOPIC_0, "Invalid topic");

        // Decode the auction end event data
        (
            address seller,
            uint256 nftTokenId,
            address highestBidder,
            uint256 amount,
            address[] memory allBidders,
            uint256[] memory allBidAmounts
        ) = abi.decode(
                data,
                (address, uint256, address, uint256, address[], uint256[])
            );

        // Store auction information
        auctions[auctionId] = AuctionInfo({
            seller: seller,
            nftContract: auctionContract,
            nftTokenId: nftTokenId,
            highestBidAmount: amount,
            highestBidder: highestBidder,
            allBidders: allBidders,
            allBidAmounts: allBidAmounts
        });

        // Transfer the NFT to the highest bidder
        IERC721(auctionContract).transferFrom(
            address(this),
            highestBidder,
            nftTokenId
        );

        // Transfer the highest bid amount to the seller
        payable(seller).transfer(amount);

        // Refund non-winning bidders
        for (uint256 i = 0; i < allBidders.length; i++) {
            if (allBidders[i] != highestBidder) {
                payable(allBidders[i]).transfer(allBidAmounts[i]);
            }
        }
    }
}
