// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {NFTCollection} from "../src/NFTCollection.sol";
import {CollectionFactory} from "../src/CollectionFactory.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

contract NFTCollectionTest is Test {
    CollectionFactory internal factory;
    NFTCollection internal collection;

    uint256 internal creatorPk = 0xA11CE;
    address internal creator;
    address internal buyer = makeAddr("buyer");
    address internal feeRecipient = makeAddr("feeRecipient");

    bytes32 internal constant VOUCHER_TYPEHASH = keccak256(
        "LazyMintVoucher(uint256 tokenId,string uri,uint256 price,address royaltyReceiver,uint96 royaltyBps)"
    );

    function setUp() public {
        creator = vm.addr(creatorPk);
        factory = new CollectionFactory(feeRecipient);

        vm.prank(creator);
        address c = factory.createCollection("1wei Genesis", "1WEI", 100, address(0), 500, "ipfs://collection.json");
        collection = NFTCollection(c);
    }

    // ------------------------------------------------------------------
    // Init / basic properties
    // ------------------------------------------------------------------

    function test_InitializedCorrectly() public view {
        assertEq(collection.name(), "1wei Genesis");
        assertEq(collection.symbol(), "1WEI");
        assertEq(collection.owner(), creator);
        assertEq(collection.maxSupply(), 100);
        assertEq(collection.contractURI(), "ipfs://collection.json");

        (address receiver, uint256 amount) = IERC2981(address(collection)).royaltyInfo(0, 10_000);
        assertEq(receiver, creator);
        assertEq(amount, 500); // 5% of 10_000
    }

    function test_CannotReinitialize() public {
        vm.expectRevert();
        collection.initialize("x", "y", creator, 0, address(0), 0, address(factory), feeRecipient, "");
    }

    function test_ImplementationCannotBeInitialized() public {
        address impl = factory.implementation();
        vm.expectRevert();
        NFTCollection(impl).initialize("x", "y", creator, 0, address(0), 0, address(factory), feeRecipient, "");
    }

    // ------------------------------------------------------------------
    // Normal minting
    // ------------------------------------------------------------------

    function test_OwnerCanMint() public {
        vm.prank(creator);
        uint256 tokenId = collection.mint(buyer, "ipfs://1.json");

        assertEq(tokenId, 0);
        assertEq(collection.ownerOf(0), buyer);
        assertEq(collection.tokenURI(0), "ipfs://1.json");
        assertEq(collection.nextTokenId(), 1);
    }

    function test_NonOwnerCannotMint() public {
        vm.prank(buyer);
        vm.expectRevert();
        collection.mint(buyer, "ipfs://1.json");
    }

    function test_MintBatch() public {
        string[] memory uris = new string[](3);
        uris[0] = "ipfs://1.json";
        uris[1] = "ipfs://2.json";
        uris[2] = "ipfs://3.json";

        vm.prank(creator);
        uint256[] memory ids = collection.mintBatch(buyer, uris);

        assertEq(ids.length, 3);
        assertEq(collection.ownerOf(ids[2]), buyer);
        assertEq(collection.nextTokenId(), 3);
    }

    function test_RevertWhen_MaxSupplyExceeded() public {
        vm.prank(creator);
        address capped = factory.createCollection("Capped", "CAP", 1, address(0), 0, "");

        vm.startPrank(creator);
        NFTCollection(capped).mint(buyer, "ipfs://1.json");
        vm.expectRevert(bytes("Max supply reached"));
        NFTCollection(capped).mint(buyer, "ipfs://2.json");
        vm.stopPrank();
    }

    // ------------------------------------------------------------------
    // Lazy minting
    // ------------------------------------------------------------------

    function _signVoucher(NFTCollection.LazyMintVoucher memory voucher, uint256 pk)
        internal
        view
        returns (bytes memory)
    {
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

        // Reconstruct the EIP-712 domain separator ourselves from the standard ERC-5267
        // `eip712Domain()` accessor (inherited from EIP712Upgradeable) rather than relying on any
        // custom accessor on NFTCollection.
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            collection.eip712Domain();
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_RedeemLazyMintVoucher() public {
        NFTCollection.LazyMintVoucher memory voucher = NFTCollection.LazyMintVoucher({
            tokenId: 42,
            uri: "ipfs://lazy.json",
            price: 1 ether,
            royaltyReceiver: creator,
            royaltyBps: 500,
            signature: ""
        });
        voucher.signature = _signVoucher(voucher, creatorPk);

        vm.deal(buyer, 1 ether);
        uint256 creatorBalBefore = creator.balance;

        vm.prank(buyer);
        collection.redeem{value: 1 ether}(voucher);

        assertEq(collection.ownerOf(42), buyer);
        assertEq(collection.tokenURI(42), "ipfs://lazy.json");
        // 2.5% platform fee taken, rest to creator
        assertEq(creator.balance - creatorBalBefore, 1 ether - (1 ether * 250) / 10_000);
        assertEq(collection.nextTokenId(), 43); // counter nudged past lazy-minted id
    }

    function test_RedeemRefundsOverpayment() public {
        NFTCollection.LazyMintVoucher memory voucher = NFTCollection.LazyMintVoucher({
            tokenId: 1,
            uri: "ipfs://lazy.json",
            price: 1 ether,
            royaltyReceiver: address(0),
            royaltyBps: 0,
            signature: ""
        });
        voucher.signature = _signVoucher(voucher, creatorPk);

        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        collection.redeem{value: 2 ether}(voucher);

        assertEq(buyer.balance, 1 ether);
    }

    function test_RevertWhen_VoucherSignedByNonOwner() public {
        uint256 attackerPk = 0xBAD;
        NFTCollection.LazyMintVoucher memory voucher = NFTCollection.LazyMintVoucher({
            tokenId: 1,
            uri: "ipfs://lazy.json",
            price: 1 ether,
            royaltyReceiver: address(0),
            royaltyBps: 0,
            signature: ""
        });
        voucher.signature = _signVoucher(voucher, attackerPk);

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(bytes("Invalid or unauthorized voucher"));
        collection.redeem{value: 1 ether}(voucher);
    }

    function test_RevertWhen_VoucherReplayed() public {
        NFTCollection.LazyMintVoucher memory voucher = NFTCollection.LazyMintVoucher({
            tokenId: 1,
            uri: "ipfs://lazy.json",
            price: 1 ether,
            royaltyReceiver: address(0),
            royaltyBps: 0,
            signature: ""
        });
        voucher.signature = _signVoucher(voucher, creatorPk);

        vm.deal(buyer, 2 ether);
        vm.startPrank(buyer);
        collection.redeem{value: 1 ether}(voucher);
        vm.expectRevert(bytes("Token already minted"));
        collection.redeem{value: 1 ether}(voucher);
        vm.stopPrank();
    }

    function test_RevertWhen_InsufficientPayment() public {
        NFTCollection.LazyMintVoucher memory voucher = NFTCollection.LazyMintVoucher({
            tokenId: 1,
            uri: "ipfs://lazy.json",
            price: 1 ether,
            royaltyReceiver: address(0),
            royaltyBps: 0,
            signature: ""
        });
        voucher.signature = _signVoucher(voucher, creatorPk);

        vm.deal(buyer, 0.5 ether);
        vm.prank(buyer);
        vm.expectRevert(bytes("Insufficient payment"));
        collection.redeem{value: 0.5 ether}(voucher);
    }

    // ------------------------------------------------------------------
    // Royalties
    // ------------------------------------------------------------------

    function test_RevertWhen_DefaultRoyaltyTooHigh() public {
        vm.prank(creator);
        vm.expectRevert(bytes("Royalty too high"));
        collection.setDefaultRoyalty(creator, 1001);
    }

    function test_OwnerCanUpdateRoyalty() public {
        vm.prank(creator);
        collection.setDefaultRoyalty(feeRecipient, 250);

        (address receiver, uint256 amount) = IERC2981(address(collection)).royaltyInfo(0, 10_000);
        assertEq(receiver, feeRecipient);
        assertEq(amount, 250);
    }

    function test_SupportsRequiredInterfaces() public view {
        assertTrue(collection.supportsInterface(type(IERC2981).interfaceId));
    }
}
