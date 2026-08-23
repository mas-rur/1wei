// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Marketplace} from "../src/Marketplace.sol";
import {CollectionFactory} from "../src/CollectionFactory.sol";
import {NFTCollection} from "../src/NFTCollection.sol";
import {MockWETH} from "./mocks/MockWETH.sol";
import {RevertingReceiver, ReentrantBidder} from "./mocks/MaliciousActors.sol";
import {MaliciousRoyaltyNFT} from "./mocks/MaliciousRoyaltyNFT.sol";

contract MarketplaceTest is Test {
    Marketplace internal market;
    CollectionFactory internal factory;
    NFTCollection internal collection;
    MockWETH internal weth;

    address internal feeRecipient = makeAddr("feeRecipient");
    address internal creator = makeAddr("creator"); // collection owner + royalty receiver (5%)
    address internal seller = makeAddr("seller");
    address internal buyer = makeAddr("buyer");
    uint256 internal tokenId;

    uint256 internal constant ROYALTY_BPS = 500; // 5%, set on the test collection
    uint256 internal constant PLATFORM_FEE_BPS = 250; // 2.5%, marketplace default

    function setUp() public {
        weth = new MockWETH();
        market = new Marketplace(feeRecipient, address(weth));
        factory = new CollectionFactory(feeRecipient);

        vm.prank(creator);
        address c = factory.createCollection("Test", "TST", 0, creator, uint96(ROYALTY_BPS), "");
        collection = NFTCollection(c);

        vm.prank(creator);
        tokenId = collection.mint(seller, "ipfs://1.json");

        vm.deal(buyer, 100 ether);
        vm.deal(seller, 10 ether);
    }

    function _approveMarketplace() internal {
        vm.prank(seller);
        collection.setApprovalForAll(address(market), true);
    }

    function _feeAndRoyalty(uint256 price) internal pure returns (uint256 royalty, uint256 fee, uint256 sellerCut) {
        royalty = (price * ROYALTY_BPS) / 10_000;
        fee = (price * PLATFORM_FEE_BPS) / 10_000;
        sellerCut = price - royalty - fee;
    }

    // ===================================================================
    // Fixed price listings
    // ===================================================================

    function test_CreateListing() public {
        _approveMarketplace();
        vm.prank(seller);
        uint256 listingId =
            market.createListing(address(collection), tokenId, address(0), 1 ether, uint64(block.timestamp + 1 days));

        (address s,,,, uint256 price,, bool active) = market.listings(listingId);
        assertEq(s, seller);
        assertEq(price, 1 ether);
        assertTrue(active);
        assertEq(market.activeListingId(address(collection), tokenId), listingId);
    }

    function test_RevertWhen_ListingWithoutApproval() public {
        vm.prank(seller);
        vm.expectRevert(bytes("Marketplace not approved"));
        market.createListing(address(collection), tokenId, address(0), 1 ether, uint64(block.timestamp + 1 days));
    }

    function test_RevertWhen_NonOwnerLists() public {
        _approveMarketplace();
        vm.prank(buyer);
        vm.expectRevert(bytes("Not owner"));
        market.createListing(address(collection), tokenId, address(0), 1 ether, uint64(block.timestamp + 1 days));
    }

    function test_BuyListingWithETH_SplitsFeeAndRoyaltyCorrectly() public {
        _approveMarketplace();
        vm.prank(seller);
        uint256 listingId =
            market.createListing(address(collection), tokenId, address(0), 1 ether, uint64(block.timestamp + 1 days));

        uint256 sellerBalBefore = seller.balance;
        uint256 creatorBalBefore = creator.balance;
        uint256 feeBalBefore = feeRecipient.balance;

        vm.prank(buyer);
        market.buy{value: 1 ether}(listingId);

        (uint256 royalty, uint256 fee, uint256 sellerCut) = _feeAndRoyalty(1 ether);

        assertEq(collection.ownerOf(tokenId), buyer);
        assertEq(creator.balance - creatorBalBefore, royalty);
        assertEq(feeRecipient.balance - feeBalBefore, fee);
        assertEq(seller.balance - sellerBalBefore, sellerCut);

        (,,,,,, bool active) = market.listings(listingId);
        assertFalse(active);
    }

    function test_BuyListingWithERC20() public {
        weth.mint(buyer, 10 ether);
        vm.prank(buyer);
        weth.approve(address(market), 10 ether);

        _approveMarketplace();
        vm.prank(seller);
        uint256 listingId = market.createListing(
            address(collection), tokenId, address(weth), 1 ether, uint64(block.timestamp + 1 days)
        );

        vm.prank(buyer);
        market.buy(listingId);

        (uint256 royalty, uint256 fee, uint256 sellerCut) = _feeAndRoyalty(1 ether);
        assertEq(collection.ownerOf(tokenId), buyer);
        assertEq(weth.balanceOf(creator), royalty);
        assertEq(weth.balanceOf(feeRecipient), fee);
        assertEq(weth.balanceOf(seller), sellerCut);
    }

    function test_CancelListing() public {
        _approveMarketplace();
        vm.startPrank(seller);
        uint256 listingId =
            market.createListing(address(collection), tokenId, address(0), 1 ether, uint64(block.timestamp + 1 days));
        market.cancelListing(listingId);
        vm.stopPrank();

        vm.prank(buyer);
        vm.expectRevert(bytes("Listing not active"));
        market.buy{value: 1 ether}(listingId);
    }

    function test_UpdateListing() public {
        _approveMarketplace();
        vm.startPrank(seller);
        uint256 listingId =
            market.createListing(address(collection), tokenId, address(0), 1 ether, uint64(block.timestamp + 1 days));
        market.updateListing(listingId, 2 ether, uint64(block.timestamp + 2 days));
        vm.stopPrank();

        (,,,, uint256 price, uint64 expiry,) = market.listings(listingId);
        assertEq(price, 2 ether);
        assertEq(expiry, block.timestamp + 2 days);
    }

    function test_RevertWhen_BuyingExpiredListing() public {
        _approveMarketplace();
        vm.prank(seller);
        uint256 listingId =
            market.createListing(address(collection), tokenId, address(0), 1 ether, uint64(block.timestamp + 1 hours));

        vm.warp(block.timestamp + 2 hours);

        vm.prank(buyer);
        vm.expectRevert(bytes("Listing expired"));
        market.buy{value: 1 ether}(listingId);
    }

    function test_RevertWhen_SellerNoLongerOwnsNFT() public {
        _approveMarketplace();
        vm.startPrank(seller);
        uint256 listingId =
            market.createListing(address(collection), tokenId, address(0), 1 ether, uint64(block.timestamp + 1 days));
        collection.transferFrom(seller, makeAddr("someoneElse"), tokenId);
        vm.stopPrank();

        vm.prank(buyer);
        vm.expectRevert(bytes("Seller no longer owns NFT"));
        market.buy{value: 1 ether}(listingId);
    }

    function test_MarketplaceCapsExcessiveRoyalty() public {
        MaliciousRoyaltyNFT malNft = new MaliciousRoyaltyNFT();
        malNft.mint(seller, 1);
        address royaltyReceiver = makeAddr("royaltyReceiver");
        malNft.setRoyalty(royaltyReceiver, 9000); // claims a 90% royalty

        vm.startPrank(seller);
        malNft.setApprovalForAll(address(market), true);
        uint256 listingId =
            market.createListing(address(malNft), 1, address(0), 1 ether, uint64(block.timestamp + 1 days));
        vm.stopPrank();

        vm.prank(buyer);
        market.buy{value: 1 ether}(listingId);

        // Capped at Marketplace.MAX_ROYALTY_BPS (10%) regardless of the 90% the collection reported
        assertEq(royaltyReceiver.balance, 0.1 ether);
    }

    // ===================================================================
    // Auctions
    // ===================================================================

    function test_CreateAuctionEscrowsNFT() public {
        _approveMarketplace();
        vm.prank(seller);
        market.createAuction(address(collection), tokenId, 1 ether, 1 hours);

        assertEq(collection.ownerOf(tokenId), address(market));
    }

    function test_PlaceBidRefundsPreviousBidder() public {
        _approveMarketplace();
        vm.prank(seller);
        uint256 auctionId = market.createAuction(address(collection), tokenId, 1 ether, 1 hours);

        vm.prank(buyer);
        market.placeBid{value: 1 ether}(auctionId);

        address buyer2 = makeAddr("buyer2");
        vm.deal(buyer2, 5 ether);
        uint256 buyerBalBefore = buyer.balance;

        vm.prank(buyer2);
        market.placeBid{value: 1.1 ether}(auctionId); // >= 5% min increment over 1 ether

        assertEq(buyer.balance - buyerBalBefore, 1 ether);
        (,,,, uint256 highestBid, address highestBidder,,,) = market.auctions(auctionId);
        assertEq(highestBidder, buyer2);
        assertEq(highestBid, 1.1 ether);
    }

    function test_RevertWhen_BidBelowMinIncrement() public {
        _approveMarketplace();
        vm.prank(seller);
        uint256 auctionId = market.createAuction(address(collection), tokenId, 1 ether, 1 hours);

        vm.prank(buyer);
        market.placeBid{value: 1 ether}(auctionId);

        address buyer2 = makeAddr("buyer2");
        vm.deal(buyer2, 5 ether);
        vm.prank(buyer2);
        vm.expectRevert(bytes("Bid too low"));
        market.placeBid{value: 1.02 ether}(auctionId); // needs >= 1.05 ether
    }

    function test_RevertWhen_SellerBidsOnOwnAuction() public {
        _approveMarketplace();
        vm.prank(seller);
        uint256 auctionId = market.createAuction(address(collection), tokenId, 1 ether, 1 hours);

        vm.deal(seller, 2 ether);
        vm.prank(seller);
        vm.expectRevert(bytes("Seller cannot bid on own auction"));
        market.placeBid{value: 1 ether}(auctionId);
    }

    function test_AuctionExtendsOnLateBid() public {
        _approveMarketplace();
        vm.prank(seller);
        uint256 auctionId = market.createAuction(address(collection), tokenId, 1 ether, 10 minutes);

        (,,,,,, uint64 endTimeBefore,,) = market.auctions(auctionId);
        vm.warp(endTimeBefore - 4 minutes); // inside the 5-minute anti-snipe window

        vm.prank(buyer);
        market.placeBid{value: 1 ether}(auctionId);

        (,,,,,, uint64 endTimeAfter,,) = market.auctions(auctionId);
        assertEq(endTimeAfter, block.timestamp + 5 minutes);
        assertTrue(endTimeAfter > endTimeBefore);
    }

    function test_SettleAuctionPaysOutWinnerSellerAndRoyalty() public {
        _approveMarketplace();
        vm.prank(seller);
        uint256 auctionId = market.createAuction(address(collection), tokenId, 1 ether, 1 hours);

        vm.prank(buyer);
        market.placeBid{value: 1 ether}(auctionId);

        vm.warp(block.timestamp + 2 hours);

        uint256 sellerBalBefore = seller.balance;
        uint256 creatorBalBefore = creator.balance;
        uint256 feeBalBefore = feeRecipient.balance;

        market.settleAuction(auctionId); // callable by anyone

        (uint256 royalty, uint256 fee, uint256 sellerCut) = _feeAndRoyalty(1 ether);
        assertEq(collection.ownerOf(tokenId), buyer);
        assertEq(seller.balance - sellerBalBefore, sellerCut);
        assertEq(creator.balance - creatorBalBefore, royalty);
        assertEq(feeRecipient.balance - feeBalBefore, fee);
    }

    function test_SettleAuctionWithNoBidsReturnsNFT() public {
        _approveMarketplace();
        vm.prank(seller);
        uint256 auctionId = market.createAuction(address(collection), tokenId, 1 ether, 1 hours);

        vm.warp(block.timestamp + 2 hours);
        market.settleAuction(auctionId);

        assertEq(collection.ownerOf(tokenId), seller);
    }

    function test_CancelAuctionBeforeAnyBids() public {
        _approveMarketplace();
        vm.startPrank(seller);
        uint256 auctionId = market.createAuction(address(collection), tokenId, 1 ether, 1 hours);
        market.cancelAuction(auctionId);
        vm.stopPrank();

        assertEq(collection.ownerOf(tokenId), seller);
    }

    function test_RevertWhen_CancelAuctionAfterBid() public {
        _approveMarketplace();
        vm.prank(seller);
        uint256 auctionId = market.createAuction(address(collection), tokenId, 1 ether, 1 hours);

        vm.prank(buyer);
        market.placeBid{value: 1 ether}(auctionId);

        vm.prank(seller);
        vm.expectRevert(bytes("Bids already placed"));
        market.cancelAuction(auctionId);
    }

    function test_RevertWhen_SettlingBeforeEndTime() public {
        _approveMarketplace();
        vm.prank(seller);
        uint256 auctionId = market.createAuction(address(collection), tokenId, 1 ether, 1 hours);

        vm.expectRevert(bytes("Auction still live"));
        market.settleAuction(auctionId);
    }

    // ===================================================================
    // Pull-payment fallback & reentrancy
    // ===================================================================

    function test_PullPaymentFallbackOnFailedRefund() public {
        RevertingReceiver rejecter = new RevertingReceiver();
        vm.deal(address(rejecter), 5 ether);

        _approveMarketplace();
        vm.prank(seller);
        uint256 auctionId = market.createAuction(address(collection), tokenId, 1 ether, 1 hours);

        vm.prank(address(rejecter));
        market.placeBid{value: 1 ether}(auctionId);

        vm.prank(buyer);
        market.placeBid{value: 1.1 ether}(auctionId); // triggers a refund push to `rejecter`, which reverts

        assertEq(market.pendingWithdrawals(address(rejecter)), 1 ether);

        rejecter.setRejecting(false);
        rejecter.withdrawFrom(market);
        assertEq(address(rejecter).balance, 5 ether); // fully recovered via the pull path
    }

    function test_ReentrancyGuardBlocksReentrantBid() public {
        ReentrantBidder attacker = new ReentrantBidder(market);
        vm.deal(address(attacker), 5 ether);

        _approveMarketplace();
        vm.prank(seller);
        uint256 auctionId = market.createAuction(address(collection), tokenId, 1 ether, 1 hours);

        attacker.bid{value: 1 ether}(auctionId);
        attacker.arm();

        vm.prank(buyer);
        market.placeBid{value: 1.1 ether}(auctionId);

        // The reentrant call inside receive() must have reverted, so the refund fell back to pull payments
        assertEq(market.pendingWithdrawals(address(attacker)), 1 ether);
        (,,,, uint256 highestBid, address highestBidder,,,) = market.auctions(auctionId);
        assertEq(highestBidder, buyer);
        assertEq(highestBid, 1.1 ether);
    }

    // ===================================================================
    // Offers
    // ===================================================================

    function test_RevertWhen_MakeOfferWithoutAllowance() public {
        vm.prank(buyer);
        vm.expectRevert(bytes("Insufficient WETH allowance"));
        market.makeOffer(address(collection), tokenId, 1 ether, uint64(block.timestamp + 1 days));
    }

    function test_MakeAndAcceptOffer() public {
        weth.mint(buyer, 10 ether);
        vm.startPrank(buyer);
        weth.approve(address(market), 10 ether);
        uint256 offerId = market.makeOffer(address(collection), tokenId, 1 ether, uint64(block.timestamp + 1 days));
        vm.stopPrank();

        _approveMarketplace();
        vm.prank(seller);
        market.acceptOffer(offerId);

        (uint256 royalty, uint256 fee, uint256 sellerCut) = _feeAndRoyalty(1 ether);
        assertEq(collection.ownerOf(tokenId), buyer);
        assertEq(weth.balanceOf(creator), royalty);
        assertEq(weth.balanceOf(feeRecipient), fee);
        assertEq(weth.balanceOf(seller), sellerCut);
    }

    function test_AcceptOfferCancelsExistingListing() public {
        _approveMarketplace();
        vm.prank(seller);
        uint256 listingId =
            market.createListing(address(collection), tokenId, address(0), 5 ether, uint64(block.timestamp + 1 days));

        weth.mint(buyer, 10 ether);
        vm.startPrank(buyer);
        weth.approve(address(market), 10 ether);
        uint256 offerId = market.makeOffer(address(collection), tokenId, 1 ether, uint64(block.timestamp + 1 days));
        vm.stopPrank();

        vm.prank(seller);
        market.acceptOffer(offerId);

        (,,,,,, bool active) = market.listings(listingId);
        assertFalse(active);
    }

    function test_CancelOffer() public {
        weth.mint(buyer, 10 ether);
        vm.startPrank(buyer);
        weth.approve(address(market), 10 ether);
        uint256 offerId = market.makeOffer(address(collection), tokenId, 1 ether, uint64(block.timestamp + 1 days));
        market.cancelOffer(offerId);
        vm.stopPrank();

        _approveMarketplace();
        vm.prank(seller);
        vm.expectRevert(bytes("Offer not active"));
        market.acceptOffer(offerId);
    }

    function test_RevertWhen_AcceptingExpiredOffer() public {
        weth.mint(buyer, 10 ether);
        vm.startPrank(buyer);
        weth.approve(address(market), 10 ether);
        uint256 offerId = market.makeOffer(address(collection), tokenId, 1 ether, uint64(block.timestamp + 1 hours));
        vm.stopPrank();

        vm.warp(block.timestamp + 2 hours);

        _approveMarketplace();
        vm.prank(seller);
        vm.expectRevert(bytes("Offer expired"));
        market.acceptOffer(offerId);
    }

    function test_RevertWhen_AcceptingOfferDuringActiveAuction() public {
        _approveMarketplace();
        vm.prank(seller);
        market.createAuction(address(collection), tokenId, 1 ether, 1 hours); // escrows the NFT

        weth.mint(buyer, 10 ether);
        vm.startPrank(buyer);
        weth.approve(address(market), 10 ether);
        uint256 offerId = market.makeOffer(address(collection), tokenId, 1 ether, uint64(block.timestamp + 1 days));
        vm.stopPrank();

        vm.prank(seller);
        vm.expectRevert(bytes("Cannot accept offer during active auction"));
        market.acceptOffer(offerId);
    }

    // ===================================================================
    // Admin
    // ===================================================================

    function test_RevertWhen_PlatformFeeExceedsCap() public {
        vm.expectRevert(bytes("Fee too high"));
        market.setPlatformFeeBps(1001);
    }

    function test_OnlyOwnerCanSetPlatformFee() public {
        vm.prank(buyer);
        vm.expectRevert();
        market.setPlatformFeeBps(300);
    }

    function test_PauseBlocksNewListingsButNotCancellation() public {
        _approveMarketplace();
        vm.prank(seller);
        uint256 listingId =
            market.createListing(address(collection), tokenId, address(0), 1 ether, uint64(block.timestamp + 1 days));

        market.pause();

        vm.prank(seller);
        vm.expectRevert();
        market.createListing(address(collection), tokenId, address(0), 1 ether, uint64(block.timestamp + 1 days));

        // Existing listings can still be cancelled while paused
        vm.prank(seller);
        market.cancelListing(listingId);

        (,,,,,, bool active) = market.listings(listingId);
        assertFalse(active);
    }
}
