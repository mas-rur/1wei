// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title Marketplace
/// @notice The 1wei marketplace: fixed-price listings, English auctions, and offers, for any ERC-721
///         collection (not just ones created through CollectionFactory). Charges a platform fee and
///         honors EIP-2981 creator royalties on every sale.
///
/// @dev Custody model (deliberately asymmetric, see README for the full rationale):
///        - Fixed-price listings are NON-CUSTODIAL. The seller keeps the NFT and simply approves the
///          marketplace; ownership/approval is re-checked at `buy` time. This is cheaper, lets sellers
///          keep using/displaying the NFT elsewhere, and cancellation is a single storage write.
///        - Auctions ARE CUSTODIAL. The NFT is transferred into escrow when the auction is created,
///          because bidders lock up real capital over the auction's lifetime and must be able to trust
///          the underlying asset can't be sold or moved out from under them mid-auction.
///        - Offers are NON-CUSTODIAL and ERC20-only (e.g. WETH). No funds are escrowed upfront — the
///          offerer's allowance is simply pulled at `acceptOffer` time. This lets one wallet have many
///          simultaneous open offers without locking capital in each one.
///
///      Every function that moves value follows checks-effects-interactions and is `nonReentrant`.
///      ETH payouts use a "push, then fall back to pull" pattern (`_sendETH`) so a single malicious or
///      broken recipient (a royalty receiver, a seller, an outbid bidder) can never block a sale,
///      auction settlement, or another bidder's refund.
contract Marketplace is IERC721Receiver, ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------

    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Absolute ceiling the platform fee can ever be set to (10%), regardless of owner action.
    uint256 public constant MAX_PLATFORM_FEE_BPS = 1_000;

    /// @notice Defensive cap on royalties actually paid out, applied on top of whatever a collection's
    ///         `royaltyInfo` reports. Protects sellers from a malicious or misconfigured NFT contract
    ///         claiming an unreasonable royalty (e.g. 100%) that would otherwise eat the entire sale.
    uint256 public constant MAX_ROYALTY_BPS = 1_000;

    uint256 public constant MIN_AUCTION_DURATION = 10 minutes;
    uint256 public constant MAX_AUCTION_DURATION = 30 days;

    /// @notice Minimum raise required over the current highest bid (5%).
    uint256 public constant MIN_BID_INCREMENT_BPS = 500;

    /// @notice Anti-snipe: a bid placed within this window of the scheduled end pushes the end back out.
    uint256 public constant EXTENSION_WINDOW = 5 minutes;
    uint256 public constant EXTENSION_DURATION = 5 minutes;

    /// @notice Gas stipend for the optimistic ETH push in `_sendETH` before falling back to pull.
    ///         Enough for a simple receive()/fallback, not enough for a recipient to do meaningful
    ///         reentrant work — which is fine, since we're nonReentrant anyway and this is defense in
    ///         depth against gas-griefing rather than the primary reentrancy protection.
    uint256 private constant ETH_TRANSFER_GAS = 30_000;

    // ---------------------------------------------------------------------
    // State
    // ---------------------------------------------------------------------

    uint256 public platformFeeBps = 250; // 2.5%
    address public feeRecipient;

    /// @notice Canonical WETH (or equivalent) address required as the `paymentToken` for all Offers.
    address public immutable WETH;

    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        address paymentToken; // address(0) = native ETH
        uint256 price;
        uint64 expiry;
        bool active;
    }

    struct Auction {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 reservePrice;
        uint256 highestBid;
        address highestBidder;
        uint64 endTime;
        bool active;
        bool settled;
    }

    struct Offer {
        address offerer;
        address nftContract;
        uint256 tokenId;
        address paymentToken; // ERC20 only (WETH)
        uint256 price;
        uint64 expiry;
        bool active;
    }

    mapping(uint256 listingId => Listing) public listings;
    uint256 public nextListingId = 1;
    /// @dev nftContract => tokenId => listingId currently active for it (0 = none). Lets us cheaply
    ///      block overlapping listings/auctions on the same token without scanning.
    mapping(address nftContract => mapping(uint256 tokenId => uint256 listingId)) public activeListingId;

    mapping(uint256 auctionId => Auction) public auctions;
    uint256 public nextAuctionId = 1;
    mapping(address nftContract => mapping(uint256 tokenId => uint256 auctionId)) public activeAuctionId;

    mapping(uint256 offerId => Offer) public offers;
    uint256 public nextOfferId = 1;

    /// @notice Pull-payment balances. Filled when a direct ETH push to a recipient fails (auction
    ///         refund to a bidder whose receive() reverts or runs out of gas, etc).
    mapping(address account => uint256 amount) public pendingWithdrawals;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event ListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint64 expiry
    );
    event ListingUpdated(uint256 indexed listingId, uint256 newPrice, uint64 newExpiry);
    event ListingCancelled(uint256 indexed listingId);
    event ItemSold(
        uint256 indexed listingId,
        address indexed buyer,
        address indexed seller,
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 royaltyAmount,
        uint256 platformFeeAmount
    );

    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 reservePrice,
        uint64 endTime
    );
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 amount);
    event AuctionExtended(uint256 indexed auctionId, uint64 newEndTime);
    event AuctionSettled(uint256 indexed auctionId, address indexed winner, uint256 amount);
    event AuctionCancelled(uint256 indexed auctionId);

    event OfferCreated(
        uint256 indexed offerId,
        address indexed offerer,
        address indexed nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint64 expiry
    );
    event OfferCancelled(uint256 indexed offerId);
    event OfferAccepted(
        uint256 indexed offerId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 royaltyAmount,
        uint256 platformFeeAmount
    );

    event Withdrawn(address indexed account, uint256 amount);
    event PlatformFeeUpdated(uint256 newBps);
    event FeeRecipientUpdated(address indexed newRecipient);

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    constructor(address feeRecipient_, address weth_) Ownable(msg.sender) {
        require(feeRecipient_ != address(0) && weth_ != address(0), "Zero address");
        feeRecipient = feeRecipient_;
        WETH = weth_;
    }

    // ===================================================================
    // Fixed price listings
    // ===================================================================

    function createListing(
        address nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint64 expiry
    ) external whenNotPaused nonReentrant returns (uint256 listingId) {
        require(price > 0, "Price must be > 0");
        require(expiry > block.timestamp, "Expiry in past");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not owner");
        require(_isApprovedForMarketplace(nftContract, msg.sender, tokenId), "Marketplace not approved");
        require(activeAuctionId[nftContract][tokenId] == 0, "Active auction exists");

        listingId = nextListingId++;
        listings[listingId] = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            paymentToken: paymentToken,
            price: price,
            expiry: expiry,
            active: true
        });
        activeListingId[nftContract][tokenId] = listingId;

        emit ListingCreated(listingId, msg.sender, nftContract, tokenId, paymentToken, price, expiry);
    }

    function updateListing(uint256 listingId, uint256 newPrice, uint64 newExpiry) external {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(listing.seller == msg.sender, "Not seller");
        require(newPrice > 0, "Price must be > 0");
        require(newExpiry > block.timestamp, "Expiry in past");

        listing.price = newPrice;
        listing.expiry = newExpiry;
        emit ListingUpdated(listingId, newPrice, newExpiry);
    }

    function cancelListing(uint256 listingId) external {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(listing.seller == msg.sender, "Not seller");

        listing.active = false;
        activeListingId[listing.nftContract][listing.tokenId] = 0;
        emit ListingCancelled(listingId);
    }

    function buy(uint256 listingId) external payable whenNotPaused nonReentrant {
        Listing memory listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(block.timestamp <= listing.expiry, "Listing expired");
        require(IERC721(listing.nftContract).ownerOf(listing.tokenId) == listing.seller, "Seller no longer owns NFT");

        // Effects
        listings[listingId].active = false;
        activeListingId[listing.nftContract][listing.tokenId] = 0;

        (address royaltyReceiver, uint256 royaltyAmount, uint256 feeAmount, uint256 sellerProceeds) =
            _calculateFees(listing.nftContract, listing.tokenId, listing.price);

        // Interactions
        if (listing.paymentToken == address(0)) {
            require(msg.value == listing.price, "Incorrect ETH amount");
            if (royaltyAmount > 0) _sendETH(royaltyReceiver, royaltyAmount);
            if (feeAmount > 0) _sendETH(feeRecipient, feeAmount);
            _sendETH(listing.seller, sellerProceeds);
        } else {
            require(msg.value == 0, "ETH not accepted for this listing");
            IERC20 token = IERC20(listing.paymentToken);
            if (royaltyAmount > 0) token.safeTransferFrom(msg.sender, royaltyReceiver, royaltyAmount);
            if (feeAmount > 0) token.safeTransferFrom(msg.sender, feeRecipient, feeAmount);
            token.safeTransferFrom(msg.sender, listing.seller, sellerProceeds);
        }

        IERC721(listing.nftContract).safeTransferFrom(listing.seller, msg.sender, listing.tokenId);

        emit ItemSold(
            listingId, msg.sender, listing.seller, listing.nftContract, listing.tokenId, listing.price, royaltyAmount, feeAmount
        );
    }

    // ===================================================================
    // English auctions (custodial — NFT escrowed for the auction's duration)
    // ===================================================================

    function createAuction(address nftContract, uint256 tokenId, uint256 reservePrice, uint64 duration)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 auctionId)
    {
        require(duration >= MIN_AUCTION_DURATION && duration <= MAX_AUCTION_DURATION, "Invalid duration");
        require(activeListingId[nftContract][tokenId] == 0, "Active listing exists");
        require(activeAuctionId[nftContract][tokenId] == 0, "Active auction exists");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not owner");

        auctionId = nextAuctionId++;
        uint64 endTime = uint64(block.timestamp) + duration;
        auctions[auctionId] = Auction({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            reservePrice: reservePrice,
            highestBid: 0,
            highestBidder: address(0),
            endTime: endTime,
            active: true,
            settled: false
        });
        activeAuctionId[nftContract][tokenId] = auctionId;

        // Escrow: bidders must be able to trust the seller can't move the asset mid-auction.
        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);

        emit AuctionCreated(auctionId, msg.sender, nftContract, tokenId, reservePrice, endTime);
    }

    function placeBid(uint256 auctionId) external payable whenNotPaused nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(auction.active, "Auction not active");
        require(block.timestamp < auction.endTime, "Auction ended");
        require(msg.sender != auction.seller, "Seller cannot bid on own auction");

        uint256 minBid;
        if (auction.highestBid == 0) {
            minBid = auction.reservePrice == 0 ? 1 : auction.reservePrice;
        } else {
            minBid = auction.highestBid + (auction.highestBid * MIN_BID_INCREMENT_BPS) / BPS_DENOMINATOR;
        }
        require(msg.value >= minBid, "Bid too low");

        address previousBidder = auction.highestBidder;
        uint256 previousBid = auction.highestBid;

        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;

        if (previousBidder != address(0)) {
            _sendETH(previousBidder, previousBid);
        }

        if (auction.endTime - block.timestamp < EXTENSION_WINDOW) {
            auction.endTime = uint64(block.timestamp) + uint64(EXTENSION_DURATION);
            emit AuctionExtended(auctionId, auction.endTime);
        }

        emit BidPlaced(auctionId, msg.sender, msg.value);
    }

    /// @notice Settle an ended auction. Callable by anyone (keeps things moving even if the seller or
    ///         winner goes quiet) once `endTime` has passed.
    function settleAuction(uint256 auctionId) external nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(auction.active, "Auction not active");
        require(block.timestamp >= auction.endTime, "Auction still live");
        require(!auction.settled, "Already settled");

        auction.settled = true;
        auction.active = false;
        activeAuctionId[auction.nftContract][auction.tokenId] = 0;

        if (auction.highestBidder == address(0) || auction.highestBid < auction.reservePrice) {
            // No bids, or reserve not met: return the NFT to the seller, nothing to pay out.
            IERC721(auction.nftContract).safeTransferFrom(address(this), auction.seller, auction.tokenId);
            emit AuctionSettled(auctionId, address(0), 0);
            return;
        }

        (address royaltyReceiver, uint256 royaltyAmount, uint256 feeAmount, uint256 sellerProceeds) =
            _calculateFees(auction.nftContract, auction.tokenId, auction.highestBid);

        if (royaltyAmount > 0) _sendETH(royaltyReceiver, royaltyAmount);
        if (feeAmount > 0) _sendETH(feeRecipient, feeAmount);
        _sendETH(auction.seller, sellerProceeds);

        IERC721(auction.nftContract).safeTransferFrom(address(this), auction.highestBidder, auction.tokenId);

        emit AuctionSettled(auctionId, auction.highestBidder, auction.highestBid);
    }

    /// @notice Only cancellable while there are no bids — once someone has committed capital, the
    ///         seller can no longer unilaterally pull out.
    function cancelAuction(uint256 auctionId) external nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(auction.active, "Auction not active");
        require(auction.seller == msg.sender, "Not seller");
        require(auction.highestBidder == address(0), "Bids already placed");

        auction.active = false;
        auction.settled = true;
        activeAuctionId[auction.nftContract][auction.tokenId] = 0;

        IERC721(auction.nftContract).safeTransferFrom(address(this), auction.seller, auction.tokenId);

        emit AuctionCancelled(auctionId);
    }

    // ===================================================================
    // Offers (non-custodial, ERC20/WETH only — works on listed AND unlisted NFTs)
    // ===================================================================

    function makeOffer(address nftContract, uint256 tokenId, uint256 price, uint64 expiry)
        external
        whenNotPaused
        returns (uint256 offerId)
    {
        require(price > 0, "Price must be > 0");
        require(expiry > block.timestamp, "Expiry in past");
        require(
            IERC20(WETH).allowance(msg.sender, address(this)) >= price, "Insufficient WETH allowance"
        );

        offerId = nextOfferId++;
        offers[offerId] = Offer({
            offerer: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            paymentToken: WETH,
            price: price,
            expiry: expiry,
            active: true
        });

        emit OfferCreated(offerId, msg.sender, nftContract, tokenId, WETH, price, expiry);
    }

    function cancelOffer(uint256 offerId) external {
        Offer storage offer = offers[offerId];
        require(offer.active, "Offer not active");
        require(offer.offerer == msg.sender, "Not offerer");

        offer.active = false;
        emit OfferCancelled(offerId);
    }

    function acceptOffer(uint256 offerId) external whenNotPaused nonReentrant {
        Offer memory offer = offers[offerId];
        require(offer.active, "Offer not active");
        require(block.timestamp <= offer.expiry, "Offer expired");
        require(activeAuctionId[offer.nftContract][offer.tokenId] == 0, "Cannot accept offer during active auction");
        require(IERC721(offer.nftContract).ownerOf(offer.tokenId) == msg.sender, "Not owner of NFT");
        require(
            _isApprovedForMarketplace(offer.nftContract, msg.sender, offer.tokenId), "Marketplace not approved"
        );

        // Effects
        offers[offerId].active = false;

        uint256 existingListingId = activeListingId[offer.nftContract][offer.tokenId];
        if (existingListingId != 0) {
            listings[existingListingId].active = false;
            activeListingId[offer.nftContract][offer.tokenId] = 0;
            emit ListingCancelled(existingListingId);
        }

        (address royaltyReceiver, uint256 royaltyAmount, uint256 feeAmount, uint256 sellerProceeds) =
            _calculateFees(offer.nftContract, offer.tokenId, offer.price);

        // Interactions
        IERC20 token = IERC20(offer.paymentToken);
        if (royaltyAmount > 0) token.safeTransferFrom(offer.offerer, royaltyReceiver, royaltyAmount);
        if (feeAmount > 0) token.safeTransferFrom(offer.offerer, feeRecipient, feeAmount);
        token.safeTransferFrom(offer.offerer, msg.sender, sellerProceeds);

        IERC721(offer.nftContract).safeTransferFrom(msg.sender, offer.offerer, offer.tokenId);

        emit OfferAccepted(
            offerId, msg.sender, offer.nftContract, offer.tokenId, offer.price, royaltyAmount, feeAmount
        );
    }

    // ===================================================================
    // Fee / royalty math
    // ===================================================================

    function _calculateFees(address nftContract, uint256 tokenId, uint256 salePrice)
        internal
        view
        returns (address royaltyReceiver, uint256 royaltyAmount, uint256 feeAmount, uint256 sellerProceeds)
    {
        feeAmount = (salePrice * platformFeeBps) / BPS_DENOMINATOR;

        // Wrapped in try/catch: EIP-721 requires ERC-165 support, but we accept arbitrary third-party
        // collections here, and a single non-compliant or misbehaving contract must not be able to
        // brick sales for itself by reverting fee calculation — it should just be treated as having no
        // royalty rather than blocking the trade entirely.
        try IERC165(nftContract).supportsInterface(type(IERC2981).interfaceId) returns (bool supported) {
            if (supported) {
                try IERC2981(nftContract).royaltyInfo(tokenId, salePrice) returns (address receiver, uint256 amount) {
                    royaltyReceiver = receiver;
                    royaltyAmount = amount;
                } catch {
                    royaltyReceiver = address(0);
                    royaltyAmount = 0;
                }
            }
        } catch {
            royaltyReceiver = address(0);
            royaltyAmount = 0;
        }

        if (royaltyAmount > 0) {
            uint256 maxRoyalty = (salePrice * MAX_ROYALTY_BPS) / BPS_DENOMINATOR;
            if (royaltyAmount > maxRoyalty) royaltyAmount = maxRoyalty;
            if (royaltyReceiver == address(0)) royaltyAmount = 0;
        }

        // Belt-and-suspenders: never let fee + royalty exceed the sale price.
        if (feeAmount + royaltyAmount > salePrice) {
            royaltyAmount = salePrice - feeAmount;
        }

        sellerProceeds = salePrice - feeAmount - royaltyAmount;
    }

    /// @dev Optimistic push with a bounded gas stipend; on failure, credits the pull-payment ledger
    ///      instead of reverting the whole sale/auction/settlement.
    function _sendETH(address to, uint256 amount) internal {
        (bool success,) = payable(to).call{value: amount, gas: ETH_TRANSFER_GAS}("");
        if (!success) {
            pendingWithdrawals[to] += amount;
        }
    }

    function _isApprovedForMarketplace(address nftContract, address owner_, uint256 tokenId)
        internal
        view
        returns (bool)
    {
        IERC721 nft = IERC721(nftContract);
        return nft.isApprovedForAll(owner_, address(this)) || nft.getApproved(tokenId) == address(this);
    }

    // ===================================================================
    // Withdrawals
    // ===================================================================

    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        pendingWithdrawals[msg.sender] = 0;

        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdraw failed");

        emit Withdrawn(msg.sender, amount);
    }

    // ===================================================================
    // Admin
    // ===================================================================

    function setPlatformFeeBps(uint256 newBps) external onlyOwner {
        require(newBps <= MAX_PLATFORM_FEE_BPS, "Fee too high");
        platformFeeBps = newBps;
        emit PlatformFeeUpdated(newBps);
    }

    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Zero address");
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(newRecipient);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ===================================================================
    // IERC721Receiver
    // ===================================================================

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
