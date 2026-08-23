// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {NFTCollection} from "./NFTCollection.sol";

/// @title CollectionFactory
/// @notice Deploys new NFTCollection instances as minimal proxies (EIP-1167 clones) so that creating a
///         collection costs a fraction of deploying a full ERC-721 contract. All clones point at the
///         same immutable `implementation` contract's logic; only storage is per-clone.
contract CollectionFactory is Ownable {
    /// @notice The NFTCollection deployed once and reused as the clone target for every collection.
    address public immutable implementation;

    /// @notice Where the 2.5% platform fee cut of lazy-mint sales is sent for every new collection.
    /// @dev Existing collections capture this value at creation time; updating it here only affects
    ///      collections created afterwards. Marketplace secondary-sale fees are configured separately
    ///      on the Marketplace contract.
    address public platformFeeRecipient;

    address[] public allCollections;
    mapping(address creator => address[] collections) public collectionsByCreator;
    mapping(address collection => bool exists) public isCollection;

    event CollectionCreated(
        address indexed creator, address indexed collection, string name, string symbol, uint256 maxSupply
    );
    event PlatformFeeRecipientUpdated(address indexed recipient);

    constructor(address platformFeeRecipient_) Ownable(msg.sender) {
        require(platformFeeRecipient_ != address(0), "Zero address");
        implementation = address(new NFTCollection());
        platformFeeRecipient = platformFeeRecipient_;
    }

    /// @param name_ ERC-721 name
    /// @param symbol_ ERC-721 symbol
    /// @param maxSupply_ 0 = uncapped
    /// @param royaltyReceiver_ address(0) defaults to msg.sender (the creator)
    /// @param royaltyBps_ default EIP-2981 royalty, max 1000 (10%)
    /// @param contractURI_ OpenSea-style collection metadata URI (banner/description/socials JSON on IPFS)
    function createCollection(
        string calldata name_,
        string calldata symbol_,
        uint256 maxSupply_,
        address royaltyReceiver_,
        uint96 royaltyBps_,
        string calldata contractURI_
    ) external returns (address collection) {
        collection = Clones.clone(implementation);

        NFTCollection(collection).initialize(
            name_,
            symbol_,
            msg.sender,
            maxSupply_,
            royaltyReceiver_ == address(0) ? msg.sender : royaltyReceiver_,
            royaltyBps_,
            address(this),
            platformFeeRecipient,
            contractURI_
        );

        allCollections.push(collection);
        collectionsByCreator[msg.sender].push(collection);
        isCollection[collection] = true;

        emit CollectionCreated(msg.sender, collection, name_, symbol_, maxSupply_);
    }

    function getCollectionsByCreator(address creator) external view returns (address[] memory) {
        return collectionsByCreator[creator];
    }

    function totalCollections() external view returns (uint256) {
        return allCollections.length;
    }

    function setPlatformFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "Zero address");
        platformFeeRecipient = recipient;
        emit PlatformFeeRecipientUpdated(recipient);
    }
}
