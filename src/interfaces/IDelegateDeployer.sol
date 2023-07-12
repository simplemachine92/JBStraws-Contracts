// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IDelegateDeployer {
    event DelegateDeployed(uint256 projectId, address delegate, address directory, address caller);

    struct DeployMyDelegateData {
        address[] allowList;
    }

    function delegateImplementation() external view returns (address);
    function delegatesRegistry() external view returns (address);
    function deployDelegateFor(
        uint256 _projectId,
        DeployMyDelegateData memory _deployMyDelegateData,
        address _directory
    ) external returns (address delegate);
}
