// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

/// @notice A deliberately misconfigured/malicious ERC-721 that can report an unreasonable royalty
///         (e.g. 90%) via EIP-2981. Used to prove the Marketplace's own `MAX_ROYALTY_BPS` cap protects
///         sellers even against a collection contract that can't be trusted.
contract MaliciousRoyaltyNFT is ERC721, IERC2981 {
    address public royaltyReceiver;
    uint256 public royaltyBpsClaimed; // intentionally NOT bounded to <= 10_000 basis points logic

    constructor() ERC721("Malicious", "MAL") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function setRoyalty(address receiver, uint256 bps) external {
        royaltyReceiver = receiver;
        royaltyBpsClaimed = bps;
    }

    function royaltyInfo(uint256, uint256 salePrice) external view returns (address, uint256) {
        return (royaltyReceiver, (salePrice * royaltyBpsClaimed) / 10_000);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, IERC2981) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }
}
