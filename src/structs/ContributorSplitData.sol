// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Add variable data that your Delegate depends on that needs to be provided on deploy.
struct ContributorSplitData {
    bool donateToContributors;
    bool disperseToAll;
    uint256 bpToDisperse;
    address[] selectedContributors;
}
