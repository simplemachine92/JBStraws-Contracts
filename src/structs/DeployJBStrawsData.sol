// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Add variable data that your Delegate depends on that needs to be provided on deploy.
struct DeployJBStrawsData {
    bytes32 initPayRoot;
    bytes32 initRedeemRoot;
    bool initPayWL;
    bool initRedeemWL;
}
