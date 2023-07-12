// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {MyDelegate} from "../src/MyDelegate.sol";
import {MyDelegateProjectDeployer} from "../src/MyDelegateProjectDeployer.sol";
import {IJBDelegatesRegistry} from "@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol";
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {JBGlobalFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {MyDelegateDeployer} from "./../src/MyDelegateDeployer.sol";
import {MyDelegateProjectDeployer} from "./../src/MyDelegateProjectDeployer.sol";
import {IDelegateProjectDeployer} from "../src/interfaces/IDelegateProjectDeployer.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import "@jbx-protocol/juice-delegates-registry/src/JBDelegatesRegistry.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../src/structs/LaunchProjectData.sol";
import "../src/structs/LaunchFundingCyclesData.sol";
import "../src/structs/DeployMyDelegateData.sol";

contract MyDelegateTest_Unit is Test {
    using stdStorage for StdStorage;

    JBDelegatesRegistry delegatesRegistry;
    MyDelegateProjectDeployer dDeployer;
    IDelegateProjectDeployer pDeployer;
    MyDelegate _delegateImplementation;

    address owner = address(bytes20(keccak256("owner")));
    address reserveBeneficiary = address(bytes20(keccak256("reserveBeneficiary")));
    address mockJBDirectory = address(bytes20(keccak256("mockJBDirectory")));
    address mockTokenUriResolver = address(bytes20(keccak256("mockTokenUriResolver")));
    address mockTerminalAddress = address(bytes20(keccak256("mockTerminalAddress")));
    address mockJBController = address(bytes20(keccak256("mockJBController")));
    address mockJBFundingCycleStore = address(bytes20(keccak256("mockJBFundingCycleStore")));
    address mockJBOperatorStore = address(bytes20(keccak256("mockJBOperatorStore")));
    address mockJBProjects = address(bytes20(keccak256("mockJBProjects")));
    uint256 projectId = 69;
    string fcMemo = "meemoo";

    function setUp() public {
        vm.label(owner, "owner");
        
        vm.label(mockTokenUriResolver, "mockTokenUriResolver");
        vm.label(mockTerminalAddress, "mockTerminalAddress");
        vm.label(mockJBController, "mockJBController");
        vm.label(mockJBDirectory, "mockJBDirectory");
        vm.label(mockJBFundingCycleStore, "mockJBFundingCycleStore");
        vm.label(mockJBProjects, "mockJBProjects");
        vm.etch(mockJBController, new bytes(0x69));
        vm.etch(mockJBDirectory, new bytes(0x69));
        vm.etch(mockJBFundingCycleStore, new bytes(0x69));
        vm.etch(mockTokenUriResolver, new bytes(0x69));
        vm.etch(mockTerminalAddress, new bytes(0x69));
        vm.etch(mockJBProjects, new bytes(0x69));

        _delegateImplementation = new MyDelegate();
       
        delegatesRegistry = new JBDelegatesRegistry(IJBDelegatesRegistry(mockJBDirectory));

        MyDelegateDeployer _delegateDeployer = new MyDelegateDeployer(_delegateImplementation, delegatesRegistry);
        dDeployer = new MyDelegateProjectDeployer(
              _delegateDeployer,
              IJBOperatorStore(mockJBOperatorStore)
            );

        pDeployer = IDelegateProjectDeployer(address(dDeployer));
    }

    function testLaunchProject(uint128 previousProjectId) public {
        // MyDelegate _myDelegate = new MyDelegate();

        vm.assume(previousProjectId < type(uint88).max);

        (
            DeployMyDelegateData memory delegateData,
            LaunchProjectData memory launchProjectData
        ) = createData();


        vm.mockCall(mockJBDirectory, abi.encodeWithSelector(IJBDirectory.projects.selector), abi.encode(mockJBProjects));
        vm.mockCall(mockJBProjects, abi.encodeWithSelector(IERC721.ownerOf.selector), abi.encode(owner));
        vm.mockCall(mockJBProjects, abi.encodeWithSelector(IJBProjects.count.selector), abi.encode(previousProjectId));
        vm.mockCall(mockJBController, abi.encodeWithSelector(IJBController3_1.launchProjectFor.selector), abi.encode(true));
        uint256 _projectId = dDeployer.launchProjectFor(owner, delegateData, launchProjectData, IJBController3_1(mockJBController));

        /* _pDeployer.launchProjectFor(address(0), ) */

        assertEq(previousProjectId, _projectId - 1);
    }

    function createData()
        internal
        view
        returns (
            DeployMyDelegateData memory delegateData,
            LaunchProjectData memory launchProjectData
        )
    {
        address[] memory aList = new address[](1);
        aList[0] = owner;

        delegateData = DeployMyDelegateData({
            allowList: aList
        });

        JBProjectMetadata memory projectMetadata;
        JBFundingCycleData memory data;
        JBFundingCycleMetadata memory metadata;
        JBGroupedSplits[] memory groupedSplits;
        JBFundAccessConstraints[] memory fundAccessConstraints;
        IJBPaymentTerminal[] memory terminals;
        projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});
        data = JBFundingCycleData({
            duration: 14,
            weight: 10 ** 18,
            discountRate: 450000000,
            ballot: IJBFundingCycleBallot(address(0))
        });
        metadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({
                allowSetTerminals: false,
                allowSetController: false,
                pauseTransfers: false
            }),
            reservedRate: 5000, //50%
            redemptionRate: 5000, //50%
            ballotRedemptionRate: 0,
            pausePay: false,
            pauseDistributions: false,
            pauseRedeem: false,
            pauseBurn: false,
            allowMinting: false,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            preferClaimedTokenOverride: false,
            useTotalOverflowForRedemptions: false,
            useDataSourceForPay: false,
            useDataSourceForRedeem: false,
            dataSource: address(_delegateImplementation),
            metadata: 0x00
        });
        launchProjectData = LaunchProjectData({
            projectMetadata: projectMetadata,
            data: data,
            metadata: metadata,
            mustStartAtOrAfter: 0,
            groupedSplits: groupedSplits,
            fundAccessConstraints: fundAccessConstraints,
            terminals: terminals,
            memo: fcMemo
        });
    }
}
