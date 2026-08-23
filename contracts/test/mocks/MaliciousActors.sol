// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Marketplace} from "../../src/Marketplace.sol";

/// @notice Rejects ETH while `rejecting` is true. Used to prove that a single bad recipient (e.g. a
///         royalty receiver or an outbid bidder) can never block a sale/settlement/refund — it should
///         fall back to the pull-payment ledger (`pendingWithdrawals`) instead of reverting. Rejection
///         is toggleable so the same mock can later accept the pull-payment withdrawal.
contract RevertingReceiver {
    bool public rejecting = true;

    receive() external payable {
        if (rejecting) revert("I refuse ETH");
    }

    function setRejecting(bool value) external {
        rejecting = value;
    }

    function withdrawFrom(Marketplace market) external {
        market.withdraw();
    }
}

/// @notice Attempts to re-enter `placeBid` from within its `receive()` (triggered when it gets
///         outbid and refunded). Used to prove `nonReentrant` holds even on the ETH-refund path.
contract ReentrantBidder {
    Marketplace public immutable market;
    uint256 public auctionId;
    bool public armed;

    constructor(Marketplace market_) {
        market = market_;
    }

    function bid(uint256 auctionId_) external payable {
        auctionId = auctionId_;
        market.placeBid{value: msg.value}(auctionId_);
    }

    function arm() external {
        armed = true;
    }

    receive() external payable {
        if (armed) {
            armed = false;
            // Attempt to re-enter — must revert due to nonReentrant.
            market.placeBid{value: msg.value}(auctionId);
        }
    }
}
