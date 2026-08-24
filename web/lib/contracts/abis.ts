import { parseAbi } from "viem";

/**
 * These signatures are transcribed directly from the Phase 1 Foundry contracts
 * (CollectionFactory.sol / NFTCollection.sol / Marketplace.sol). If you change a
 * contract and redeploy, update the matching ABI here too — there's no build step
 * that keeps these in sync automatically.
 */

export const collectionFactoryAbi = parseAbi([
  "function createCollection(string name_, string symbol_, uint256 maxSupply_, address royaltyReceiver_, uint96 royaltyBps_, string contractURI_) returns (address collection)",
  "function getCollectionsByCreator(address creator) view returns (address[])",
  "function totalCollections() view returns (uint256)",
  "function implementation() view returns (address)",
  "function platformFeeRecipient() view returns (address)",
  "function isCollection(address) view returns (bool)",
  "event CollectionCreated(address indexed creator, address indexed collection, string name, string symbol, uint256 maxSupply)",
]);

// Lazy minting (`redeem`) is intentionally omitted — no UI for it yet (see Phase 3 notes).
export const nftCollectionAbi = parseAbi([
  "function mint(address to, string uri) returns (uint256 tokenId)",
  "function mintBatch(address to, string[] uris) returns (uint256[] tokenIds)",
  "function ownerOf(uint256 tokenId) view returns (address)",
  "function balanceOf(address owner) view returns (uint256)",
  "function tokenURI(uint256 tokenId) view returns (string)",
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function owner() view returns (address)",
  "function maxSupply() view returns (uint256)",
  "function nextTokenId() view returns (uint256)",
  "function contractURI() view returns (string)",
  "function approve(address to, uint256 tokenId)",
  "function setApprovalForAll(address operator, bool approved)",
  "function isApprovedForAll(address owner, address operator) view returns (bool)",
  "function getApproved(uint256 tokenId) view returns (address)",
  "event Minted(address indexed to, uint256 indexed tokenId, string uri)",
]);

export const marketplaceAbi = parseAbi([
  // Listings
  "function createListing(address nftContract, uint256 tokenId, address paymentToken, uint256 price, uint64 expiry) returns (uint256 listingId)",
  "function updateListing(uint256 listingId, uint256 newPrice, uint64 newExpiry)",
  "function cancelListing(uint256 listingId)",
  "function buy(uint256 listingId) payable",
  "function listings(uint256) view returns (address seller, address nftContract, uint256 tokenId, address paymentToken, uint256 price, uint64 expiry, bool active)",
  "function activeListingId(address nftContract, uint256 tokenId) view returns (uint256)",

  // Auctions
  "function createAuction(address nftContract, uint256 tokenId, uint256 reservePrice, uint64 duration) returns (uint256 auctionId)",
  "function placeBid(uint256 auctionId) payable",
  "function settleAuction(uint256 auctionId)",
  "function cancelAuction(uint256 auctionId)",
  "function auctions(uint256) view returns (address seller, address nftContract, uint256 tokenId, uint256 reservePrice, uint256 highestBid, address highestBidder, uint64 endTime, bool active, bool settled)",
  "function activeAuctionId(address nftContract, uint256 tokenId) view returns (uint256)",
  "function MIN_BID_INCREMENT_BPS() view returns (uint256)",

  // Offers
  "function makeOffer(address nftContract, uint256 tokenId, uint256 price, uint64 expiry) returns (uint256 offerId)",
  "function cancelOffer(uint256 offerId)",
  "function acceptOffer(uint256 offerId)",
  "function offers(uint256) view returns (address offerer, address nftContract, uint256 tokenId, address paymentToken, uint256 price, uint64 expiry, bool active)",

  // Misc
  "function withdraw()",
  "function pendingWithdrawals(address) view returns (uint256)",
  "function platformFeeBps() view returns (uint256)",
  "function WETH() view returns (address)",

  // Events (used to decode return values off transaction receipts)
  "event ListingCreated(uint256 indexed listingId, address indexed seller, address indexed nftContract, uint256 tokenId, address paymentToken, uint256 price, uint64 expiry)",
  "event ItemSold(uint256 indexed listingId, address indexed buyer, address indexed seller, address nftContract, uint256 tokenId, uint256 price, uint256 royaltyAmount, uint256 platformFeeAmount)",
  "event AuctionCreated(uint256 indexed auctionId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 reservePrice, uint64 endTime)",
  "event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 amount)",
  "event AuctionSettled(uint256 indexed auctionId, address indexed winner, uint256 amount)",
  "event OfferCreated(uint256 indexed offerId, address indexed offerer, address indexed nftContract, uint256 tokenId, address paymentToken, uint256 price, uint64 expiry)",
  "event OfferAccepted(uint256 indexed offerId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 price, uint256 royaltyAmount, uint256 platformFeeAmount)",
]);
