// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/structs/LaunchProjectData.sol";
import "../src/structs/LaunchFundingCyclesData.sol";
import "../src/structs/DeployJBStrawsData.sol";
import "./helpers/TestBaseWorkflowV3.sol";
import "@jbx-protocol/juice-delegates-registry/src/JBDelegatesRegistry.sol";
import "@paulrberg/contracts/math/PRBMath.sol";

import {JBStraws} from "../src/JBStraws.sol";
import {JBStrawsProjectDeployer} from "../src/JBStrawsProjectDeployer.sol";
import {IJBDelegatesRegistry} from "@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {JBGlobalFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {JBOperatorData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBOperatorData.sol";
import {JBStrawsDeployer} from "./../src/JBStrawsDeployer.sol";
import {IJBStrawsDelegate} from "../src/interfaces/IJBStrawsDelegate.sol";
import {Merkle} from "murky/Merkle.sol";

// Inherits from "./helpers/TestBaseWorkflowV3.sol", called by super.setUp()
contract JBStrawsTest_Int is TestBaseWorkflowV3 {
    event Proof(bytes32[]);
    using JBFundingCycleMetadataResolver for JBFundingCycle;

    // Project setup params
    JBProjectMetadata _projectMetadata;
    JBFundingCycleData _data;
    JBFundingCycleMetadata _metadata;
    JBFundAccessConstraints[] _fundAccessConstraints; // Default empty
    IJBPaymentTerminal[] _terminals; // Default empty
    IJBStrawsDelegate _straws;
    Merkle _m;

    // Delegate setup params
    JBDelegatesRegistry delegatesRegistry;
    JBStraws _delegateImpl;
    JBStrawsDeployer _delegateDepl;
    DeployJBStrawsData delegateData;
    JBStrawsProjectDeployer projectDepl;

    // Assigned when project is launched
    uint256 _projectId;

    // Used in JBFundingCycleMetadata, 4500 = 45% I believe, but using 0 for testing calcs
    uint256 reservedRate = 0;

    // Used in JBFundingCycleData
    uint256 weight = 10 ** 18; // Minting 1 token per eth

    bytes32 tRoot;
    bytes32 tRoot2;

    function setUp() public override {
        // Provides us with _jbOperatorStore and _jbETHPaymentTerminal
        super.setUp();

        // Initialize
        Merkle m = new Merkle();
        _m = m;
        
        // Toy Data
        bytes32[] memory data = new bytes32[](4);
        data[0] = bytes32(uint256(uint160(address(123))));
        data[1] = bytes32(uint256(uint160(address(1234))));
        data[2] = bytes32(uint256(uint160(address(12345))));
        data[3] = bytes32(uint256(uint160(address(123456))));

        // Get Root, Proof, and Verify
        bytes32 root = m.getRoot(data);
        bytes32[] memory proof = m.getProof(data, 2); // will get proof for 0x2 value
        bool verified = m.verifyProof(root, proof, data[2]); // true!
        assertTrue(verified);

        tRoot = root;

        // Toy Data
        bytes32[] memory data2 = new bytes32[](4);
        data2[0] = bytes32(uint256(uint160(address(123))));
        data2[1] = bytes32(uint256(uint160(address(1234))));
        data2[2] = bytes32(uint256(uint160(address(12345))));
        data2[3] = bytes32(uint256(uint160(address(123456))));

        // Get Root, Proof, and Verify
        bytes32 root2 = m.getRoot(data);

        tRoot2 = root2;

        /* 
        This setup follows a DelegateProjectDeployer pattern like in https://docs.juicebox.money/dev/extensions/juice-721-delegate/
        It deploys a new JB project and funding cycle, and then attaches our delegate to that funding cycle as a DataSource and Delegate.
        */

        // Placeholder project metadata, would customize this in prod.
        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});

        // https://docs.juicebox.money/dev/extensions/juice-delegates-registry/jbdelegatesregistry/
        delegatesRegistry = new JBDelegatesRegistry(IJBDelegatesRegistry(address(0)));

        // Instance of our delegate code
        _delegateImpl = new JBStraws(_jbOperatorStore);

        // Required for our custom project deployer below, eventually attaches the delegate to the funding cycle.
        _delegateDepl = new JBStrawsDeployer(_delegateImpl, delegatesRegistry);

        // Custom deployer
        projectDepl = new JBStrawsProjectDeployer(_delegateDepl, _jbOperatorStore);

        // The following describes the funding cycle, access constraints, and metadata necessary for our project.
        _data = JBFundingCycleData({
            duration: 30 days,
            weight: weight,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });

        _metadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({
                allowSetTerminals: false,
                allowSetController: false,
                pauseTransfers: false
            }),
            reservedRate: reservedRate,
            redemptionRate: 5000,
            ballotRedemptionRate: 0,
            pausePay: false,
            pauseDistributions: false,
            pauseRedeem: false,
            pauseBurn: false,
            allowMinting: true,
            preferClaimedTokenOverride: false,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            useTotalOverflowForRedemptions: false,
            useDataSourceForPay: true,
            useDataSourceForRedeem: false,
            dataSource: address(_delegateImpl),
            metadata: 0
        });

        _fundAccessConstraints.push(
            JBFundAccessConstraints({
                terminal: _jbETHPaymentTerminal,
                token: jbLibraries().ETHToken(),
                distributionLimit: 2 ether,
                overflowAllowance: type(uint232).max,
                distributionLimitCurrency: 1, // Currency = ETH
                overflowAllowanceCurrency: 1
            })
        );

        // Imported from TestBaseWorkflowV3.sol via super.setUp() https://docs.juicebox.money/dev/learn/architecture/terminals/
        _terminals = [_jbETHPaymentTerminal];

        JBGroupedSplits[] memory _groupedSplits = new JBGroupedSplits[](1); // Default empty

        // The imported struct used by our delegate
        delegateData = DeployJBStrawsData({
            initPayRoot: tRoot,
            initRedeemRoot: tRoot2,
            initPayWL: false,
            initRedeemWL: false
        });

        // Assemble all of our previous configuration for our project deployer
         LaunchProjectData memory launchProjectData = LaunchProjectData({
            projectMetadata: _projectMetadata,
            data: _data,
            metadata: _metadata,
            mustStartAtOrAfter: 0,
            groupedSplits: _groupedSplits,
            fundAccessConstraints: _fundAccessConstraints,
            terminals: _terminals,
            memo: ""
        });


        // Blastoff
        vm.prank(address(123));
        _projectId = projectDepl.launchProjectFor(
            address(123),
            delegateData,
            launchProjectData,
            _jbController
        );

        (, JBFundingCycleMetadata memory metadata, ) = _jbController.latestConfiguredFundingCycleOf(1);

        vm.label(metadata.dataSource, "Initialized DS");

        _straws = IJBStrawsDelegate(metadata.dataSource);
    }

    function test_setOperator() public {
        // Build setOperator callData
        uint256[] memory opData = new uint256[](1);
        opData[0] = uint256(255);

        /* 
        struct JBOperatorData {
        address operator;
        uint256 domain (projectId);
        uint256[] permissionIndexes (max 255);
        }
        */

         JBOperatorData memory jbod = JBOperatorData({
          operator: address(1234),
          domain: _projectId,
          permissionIndexes: opData
         });

        // Call from project owner address
        vm.prank(address(123));
        _jbOperatorStore.setOperator(jbod);

        // Build merkle root so we can call setroot to prove permission
        bytes32[] memory data = new bytes32[](4);
        data[0] = bytes32(uint256(uint160(address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266))));
        data[1] = bytes32(uint256(uint160(address(1234))));
        data[2] = bytes32(uint256(uint160(address(12345))));
        data[3] = bytes32(uint256(uint160(address(123456))));
        bytes32 root = _m.getRoot(data);

        // Prove permission
        vm.prank(address(1234));
        _straws.setPayRoot(root);
    }

    function testFail_setOperatorWrongPermissionIndex() public {
        // Build incorrect setOperator callData
        uint256[] memory opData = new uint256[](1);
        opData[0] = uint256(9);

        /* 
        struct JBOperatorData {
        address operator;
        uint256 domain (projectId);
        uint256[] permissionIndexes (max 255);
        }
        */

         JBOperatorData memory jbod = JBOperatorData({
          operator: address(1234),
          domain: _projectId,
          permissionIndexes: opData
         });

        // Call from project owner address
        vm.prank(address(123));
        _jbOperatorStore.setOperator(jbod);

        // Build merkle root so we can call setroot to prove permission
        bytes32[] memory data = new bytes32[](4);
        data[0] = bytes32(uint256(uint160(address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266))));
        data[1] = bytes32(uint256(uint160(address(1234))));
        data[2] = bytes32(uint256(uint160(address(12345))));
        data[3] = bytes32(uint256(uint160(address(123456))));
        bytes32 root = _m.getRoot(data);

        // Prove permission
        vm.prank(address(1234));
        _straws.setPayRoot(root);
    }

    function test_diffRoots() public {
        // Toy Data
        bytes32[] memory data = new bytes32[](4);
        data[0] = bytes32(uint256(uint160(address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266))));
        data[1] = bytes32(uint256(uint160(address(1234))));
        data[2] = bytes32(uint256(uint160(address(12345))));
        data[3] = bytes32(uint256(uint160(address(123456))));

        // Get Root, Proof, and Verify
        bytes32 root = _m.getRoot(data);
        bytes32[] memory proof = _m.getProof(data, 0); // will get proof for 0x0 value

        vm.prank(address(123));
        _straws.setPayRoot(root);

        _straws.verify(proof, true, address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266));
    }

    function testFail_diffRoots() public {
        // Toy Data
        bytes32[] memory data = new bytes32[](4);
        data[0] = bytes32(uint256(uint160(address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266))));
        data[1] = bytes32(uint256(uint160(address(1234))));
        data[2] = bytes32(uint256(uint160(address(12345))));
        data[3] = bytes32(uint256(uint160(address(123456))));

        // Get Root, Proof, and Verify
        bytes32 root = _m.getRoot(data);
        bytes32[] memory proof = _m.getProof(data, 0); // will get proof for 0x0 value

        vm.prank(address(123));
        _straws.setPayRoot(root);

        _straws.verify(proof, false, address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266));
    }

    function test_SetRootByOwner() public {
        // Check for initial root
        assertEq(_straws.payRoot(), 0xa9273ce1e6b4ac4eb3d07f01103d44e3778747536780332f977c5915415fd7db);

        // Set root with admin
        vm.prank(address(123));
        _straws.setPayRoot(bytes32(""));

        // Make sure it was modified
        assertEq(_straws.payRoot(), "");
    }

    function testFail_SetRootByNonOwner() public {
        // Check for initial root
        assertEq(_straws.payRoot(), 0xa9273ce1e6b4ac4eb3d07f01103d44e3778747536780332f977c5915415fd7db);

        // Set root with admin
        vm.prank(address(124));
        _straws.setPayRoot(bytes32(""));

        // Make sure it was modified
        assertEq(_straws.payRoot(), "");
    }

    function test_PayHookAndVerifyAllowed() public {
        vm.prank(address(123));
        _straws.togglePayWhitelistEnabled();

        // Toy Data
        bytes32[] memory data = new bytes32[](4);

        data[0] = bytes32(uint256(uint160(address(123))));
        data[1] = bytes32(uint256(uint160(address(1234))));
        data[2] = bytes32(uint256(uint160(address(12345))));
        data[3] = bytes32(uint256(uint160(address(123456))));

        bytes32[] memory proof = _m.getProof(data, 0); // will get proof for 0x2 value

        vm.deal(address(123), 1 ether);
        vm.prank(address(123));
        _jbETHPaymentTerminal.pay{value: 1 ether}(
            1,
            1 ether,
            address(0),
            _multisig,
            0,
            false,
            "Take my money!",
            abi.encode(proof)
        );
    }

    function testFail_PayHookWhitelistEnabledWrongProof() public {
        vm.prank(address(123));
        _straws.togglePayWhitelistEnabled();

        // Toy Data
        bytes32[] memory data = new bytes32[](4);

        data[0] = bytes32(uint256(uint160(address(123))));
        data[1] = bytes32(uint256(uint160(address(1234))));
        data[2] = bytes32(uint256(uint160(address(12345))));
        data[3] = bytes32(uint256(uint160(address(123456))));

        bytes32[] memory proof = _m.getProof(data, 0); // will get proof for 0x2 value

        vm.deal(address(123456), 1 ether);
        vm.prank(address(123456));
        _jbETHPaymentTerminal.pay{value: 1 ether}(
            1,
            1 ether,
            address(0),
            _multisig,
            0,
            false,
            "Take my money!",
            abi.encode(proof)
        );
    }

    function test_PayHookNotAllowedWhitelistDisabled() public {
        assertEq(_straws.payWhitelistEnabled(), false);

        bytes32[] memory data = new bytes32[](4);

        data[0] = bytes32(uint256(uint160(address(123))));
        data[1] = bytes32(uint256(uint160(address(1234))));
        data[2] = bytes32(uint256(uint160(address(12345))));
        data[3] = bytes32(uint256(uint160(address(123456))));

        bytes32[] memory proof = _m.getProof(data, 0); // will get proof for 0x2 value

        vm.deal(address(129), 1 ether);
        vm.prank(address(129));
        _jbETHPaymentTerminal.pay{value: 1 ether}(
            1,
            1 ether,
            address(0),
            _multisig,
            0,
            false,
            "Take my money!",
            abi.encode(proof)
        );
    }

}
