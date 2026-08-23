// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721URIStorageUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {ERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title NFTCollection
/// @notice ERC-721 collection contract created by `CollectionFactory` as a minimal-proxy (EIP-1167)
///         clone of a single implementation. Because clones share code but not storage/constructors,
///         this contract uses OpenZeppelin's *Upgradeable* base contracts purely for their `initialize()`
///         pattern — there is no proxy admin, no upgradeability, and no delegatecall-based upgrade path.
///         Each clone is a permanent, immutable-logic collection owned by its creator.
///
/// @dev Two ways to get tokens into a collection:
///      1. `mint` / `mintBatch` — the owner (creator) mints directly, e.g. for a mint page or airdrop.
///      2. `redeem` — "lazy minting": the creator signs an off-chain `LazyMintVoucher` (EIP-712) listing
///         a tokenId/uri/price. No gas is spent, no tokens exist, until a buyer calls `redeem` with the
///         voucher and payment, at which point the token is minted straight to the buyer and payment is
///         forwarded to the creator (minus the platform fee). This lets creators list an entire drop
///         with zero upfront gas cost.
contract NFTCollection is
    Initializable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    ERC2981Upgradeable,
    OwnableUpgradeable,
    EIP712Upgradeable
{
    using ECDSA for bytes32;

    // ---------------------------------------------------------------------
    // Minimal reentrancy guard
    // ---------------------------------------------------------------------
    // Rolled by hand instead of importing OpenZeppelin's upgradeable variant: as of OpenZeppelin
    // Contracts v5.5, `ReentrancyGuardUpgradeable` was removed in favor of a "stateless" guard meant to
    // be paired with manual storage initialization, which adds more version-specific ceremony than this
    // single guarded function warrants. This is the same check-a-flag pattern, just inlined.
    uint256 private _reentrancyLock;

    modifier nonReentrant() {
        require(_reentrancyLock == 0, "Reentrant call");
        _reentrancyLock = 1;
        _;
        _reentrancyLock = 0;
    }

    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------

    /// @notice Hard ceiling on royalty basis points a creator can configure (10%). Enforced here AND
    ///         defensively re-checked by the Marketplace at sale time, so no single contract has to be
    ///         trusted alone.
    uint96 public constant MAX_ROYALTY_BPS = 1_000;

    /// @notice Platform fee (2.5%) taken on primary lazy-mint sales, mirroring the Marketplace's default
    ///         secondary-sale fee so creator economics are consistent whether a token sells before or
    ///         after its first mint.
    uint256 public constant PLATFORM_FEE_BPS = 250;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    bytes32 private constant VOUCHER_TYPEHASH = keccak256(
        "LazyMintVoucher(uint256 tokenId,string uri,uint256 price,address royaltyReceiver,uint96 royaltyBps)"
    );

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    /// @notice Next tokenId to be used by `mint`/`mintBatch`. Lazy-minted tokenIds can be chosen
    ///         arbitrarily by the creator (e.g. pre-assigned per metadata slot) and this counter is
    ///         nudged forward past any lazy-minted id so the two schemes never collide.
    uint256 public nextTokenId;

    /// @notice 0 means uncapped.
    uint256 public maxSupply;

    /// @notice The CollectionFactory that deployed this clone (informational / for indexers).
    address public factory;

    /// @notice Where the platform fee cut of lazy-mint sales is sent.
    address public platformFeeRecipient;

    /// @notice OpenSea-style contract-level metadata URI (name/description/banner/social links JSON).
    string private _contractURI;

    /// @notice Voucher signed by the collection owner authorizing anyone to mint a specific token.
    struct LazyMintVoucher {
        uint256 tokenId;
        string uri;
        uint256 price; // wei
        address royaltyReceiver; // address(0) = no per-token royalty override
        uint96 royaltyBps;
        bytes signature;
    }

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event Minted(address indexed to, uint256 indexed tokenId, string uri);
    event LazyMinted(address indexed to, uint256 indexed tokenId, uint256 price);
    event DefaultRoyaltyUpdated(address receiver, uint96 bps);
    event TokenRoyaltyUpdated(uint256 indexed tokenId, address receiver, uint96 bps);
    event ContractURIUpdated(string uri);

    // ---------------------------------------------------------------------
    // Init
    // ---------------------------------------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Locks the implementation contract itself so it can never be initialized/used directly —
        // only clones (which never execute this constructor) are meant to be initialized.
        _disableInitializers();
    }

    /// @notice Called once by CollectionFactory immediately after cloning.
    function initialize(
        string memory name_,
        string memory symbol_,
        address owner_,
        uint256 maxSupply_,
        address royaltyReceiver_,
        uint96 royaltyBps_,
        address factory_,
        address platformFeeRecipient_,
        string memory contractURI_
    ) external initializer {
        __ERC721_init(name_, symbol_);
        __ERC721URIStorage_init();
        __Ownable_init(owner_);
        __EIP712_init(name_, "1");

        maxSupply = maxSupply_;
        factory = factory_;
        platformFeeRecipient = platformFeeRecipient_;
        _contractURI = contractURI_;

        require(royaltyBps_ <= MAX_ROYALTY_BPS, "Royalty too high");
        if (royaltyBps_ > 0) {
            _setDefaultRoyalty(royaltyReceiver_, royaltyBps_);
        }
    }

    // ---------------------------------------------------------------------
    // Normal minting (owner-only, gas paid upfront)
    // ---------------------------------------------------------------------

    function mint(address to, string memory uri) public onlyOwner returns (uint256 tokenId) {
        tokenId = nextTokenId;
        _mintChecked(to, tokenId, uri);
        nextTokenId = tokenId + 1;
    }

    function mintBatch(address to, string[] memory uris) external onlyOwner returns (uint256[] memory tokenIds) {
        tokenIds = new uint256[](uris.length);
        uint256 tokenId = nextTokenId;
        for (uint256 i = 0; i < uris.length; i++) {
            _mintChecked(to, tokenId, uris[i]);
            tokenIds[i] = tokenId;
            tokenId++;
        }
        nextTokenId = tokenId;
    }

    function _mintChecked(address to, uint256 tokenId, string memory uri) private {
        if (maxSupply != 0) {
            require(tokenId < maxSupply, "Max supply reached");
        }
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        emit Minted(to, tokenId, uri);
    }

    // ---------------------------------------------------------------------
    // Lazy minting
    // ---------------------------------------------------------------------

    /// @notice Mint a token authorized by an off-chain voucher signed by the collection owner.
    /// @dev Payment (minus the platform fee) is forwarded to the current `owner()` — if ownership of
    ///      the collection changes, proceeds follow the new owner, not whoever signed historically.
    function redeem(LazyMintVoucher calldata voucher) external payable nonReentrant returns (uint256) {
        address signer = _verifyVoucher(voucher);
        require(signer == owner(), "Invalid or unauthorized voucher");
        require(_ownerOf(voucher.tokenId) == address(0), "Token already minted");
        require(msg.value >= voucher.price, "Insufficient payment");
        require(voucher.royaltyBps <= MAX_ROYALTY_BPS, "Royalty too high");
        if (maxSupply != 0) {
            require(voucher.tokenId < maxSupply, "Max supply reached");
        }

        _safeMint(msg.sender, voucher.tokenId);
        _setTokenURI(voucher.tokenId, voucher.uri);
        if (voucher.royaltyReceiver != address(0)) {
            _setTokenRoyalty(voucher.tokenId, voucher.royaltyReceiver, voucher.royaltyBps);
        }
        if (voucher.tokenId >= nextTokenId) {
            nextTokenId = voucher.tokenId + 1;
        }

        uint256 fee = (voucher.price * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
        uint256 creatorProceeds = voucher.price - fee;

        if (fee > 0) {
            (bool feeSent,) = payable(platformFeeRecipient).call{value: fee}("");
            require(feeSent, "Fee transfer failed");
        }
        (bool ownerSent,) = payable(owner()).call{value: creatorProceeds}("");
        require(ownerSent, "Payment to creator failed");

        if (msg.value > voucher.price) {
            (bool refunded,) = payable(msg.sender).call{value: msg.value - voucher.price}("");
            require(refunded, "Refund failed");
        }

        emit LazyMinted(msg.sender, voucher.tokenId, voucher.price);
        return voucher.tokenId;
    }

    function _verifyVoucher(LazyMintVoucher calldata voucher) internal view returns (address) {
        bytes32 structHash = keccak256(
            abi.encode(
                VOUCHER_TYPEHASH,
                voucher.tokenId,
                keccak256(bytes(voucher.uri)),
                voucher.price,
                voucher.royaltyReceiver,
                voucher.royaltyBps
            )
        );
        return _hashTypedDataV4(structHash).recover(voucher.signature);
    }

    /// @notice Standard ERC-5267 `eip712Domain()` (inherited from EIP712Upgradeable) already exposes
    ///         name/version/chainId/verifyingContract for off-chain signers to construct the exact
    ///         typed-data domain used by `_verifyVoucher` — no custom accessor needed here.
    // ---------------------------------------------------------------------
    // Royalties & metadata
    // ---------------------------------------------------------------------

    function setDefaultRoyalty(address receiver, uint96 feeBps) external onlyOwner {
        require(feeBps <= MAX_ROYALTY_BPS, "Royalty too high");
        _setDefaultRoyalty(receiver, feeBps);
        emit DefaultRoyaltyUpdated(receiver, feeBps);
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeBps) external onlyOwner {
        require(feeBps <= MAX_ROYALTY_BPS, "Royalty too high");
        _setTokenRoyalty(tokenId, receiver, feeBps);
        emit TokenRoyaltyUpdated(tokenId, receiver, feeBps);
    }

    function contractURI() external view returns (string memory) {
        return _contractURI;
    }

    function setContractURI(string memory uri_) external onlyOwner {
        _contractURI = uri_;
        emit ContractURIUpdated(uri_);
    }

    // ---------------------------------------------------------------------
    // Required overrides (multiple inheritance)
    // ---------------------------------------------------------------------

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
