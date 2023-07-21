// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IJBDelegatesRegistry} from "@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBDirectory} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import {DeployJBStrawsData} from "./structs/DeployJBStrawsData.sol";
import {JBStraws} from "./JBStraws.sol";

/// @notice A contract that deploys a delegate contract.
contract JBStrawsDeployer {
    event DelegateDeployed(uint256 projectId, JBStraws delegate, IJBDirectory directory, address caller);

    /// @notice This contract's current nonce, used for the Juicebox delegates registry.
    uint256 internal _nonce;

    /// @notice An implementation of the Delegate being deployed.
    JBStraws public immutable delegateImplementation;

    /// @notice A contract that stores references to deployer contracts of delegates.
    IJBDelegatesRegistry public immutable delegatesRegistry;

    /// @param _delegateImplementation The delegate implementation that will be cloned.
    /// @param _delegatesRegistry A contract that stores references to delegate deployer contracts.
    constructor(JBStraws _delegateImplementation, IJBDelegatesRegistry _delegatesRegistry) {
        delegateImplementation = _delegateImplementation;
        delegatesRegistry = _delegatesRegistry;
    }

    /// @notice Deploys a delegate for the provided project.
    /// @param _projectId The ID of the project for which the delegate will be deployed.
    /// @param _deployJBStrawsData Data necessary to deploy the delegate.
    /// @param _directory The directory of terminals and controllers for projects.
    /// @return delegate The address of the newly deployed delegate.
    function deployDelegateFor(
        uint256 _projectId,
        DeployJBStrawsData memory _deployJBStrawsData,
        IJBDirectory _directory,
        IJBController3_1 controller
    ) external returns (JBStraws delegate) {
        // Deploy the delegate clone from the implementation.
        delegate = JBStraws(Clones.clone(address(delegateImplementation)));

        // Initialize it.
        delegate.initialize(_projectId, _directory, _deployJBStrawsData, controller);

        // Add the delegate to the registry. Contract nonce starts at 1.
        delegatesRegistry.addDelegate(address(this), ++_nonce);

        emit DelegateDeployed(_projectId, delegate, _directory, msg.sender);
    }
}
