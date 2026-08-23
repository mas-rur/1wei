// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {CollectionFactory} from "../src/CollectionFactory.sol";
import {NFTCollection} from "../src/NFTCollection.sol";

contract CollectionFactoryTest is Test {
    CollectionFactory internal factory;
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        factory = new CollectionFactory(feeRecipient);
    }

    function test_CreateCollectionDeploysClone() public {
        vm.prank(alice);
        address collection = factory.createCollection("Alice Art", "ALICE", 0, address(0), 500, "");

        assertTrue(factory.isCollection(collection));
        assertEq(factory.totalCollections(), 1);
        assertEq(NFTCollection(collection).owner(), alice);
        // Clone shares logic with, but is not, the implementation
        assertTrue(collection != factory.implementation());
    }

    function test_ClonesAreIndependent() public {
        vm.prank(alice);
        address collectionA = factory.createCollection("A", "A", 0, address(0), 0, "");
        vm.prank(bob);
        address collectionB = factory.createCollection("B", "B", 0, address(0), 0, "");

        vm.prank(alice);
        NFTCollection(collectionA).mint(alice, "ipfs://a.json");

        // Minting on A must not affect B's supply or ownership
        assertEq(NFTCollection(collectionA).nextTokenId(), 1);
        assertEq(NFTCollection(collectionB).nextTokenId(), 0);
        assertEq(NFTCollection(collectionA).owner(), alice);
        assertEq(NFTCollection(collectionB).owner(), bob);

        vm.prank(alice);
        vm.expectRevert();
        NFTCollection(collectionB).mint(alice, "ipfs://x.json"); // alice isn't owner of B
    }

    function test_TracksCollectionsByCreator() public {
        vm.startPrank(alice);
        address c1 = factory.createCollection("A1", "A1", 0, address(0), 0, "");
        address c2 = factory.createCollection("A2", "A2", 0, address(0), 0, "");
        vm.stopPrank();

        address[] memory aliceCollections = factory.getCollectionsByCreator(alice);
        assertEq(aliceCollections.length, 2);
        assertEq(aliceCollections[0], c1);
        assertEq(aliceCollections[1], c2);
    }

    function test_RevertWhen_RoyaltyExceedsCap() public {
        vm.prank(alice);
        vm.expectRevert(bytes("Royalty too high"));
        factory.createCollection("A", "A", 0, address(0), 1001, "");
    }

    function test_OnlyOwnerCanUpdateFeeRecipient() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.setPlatformFeeRecipient(alice);

        address newRecipient = makeAddr("newRecipient");
        factory.setPlatformFeeRecipient(newRecipient); // called by test contract, the factory owner
        assertEq(factory.platformFeeRecipient(), newRecipient);
    }
}
