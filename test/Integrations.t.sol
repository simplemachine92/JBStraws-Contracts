// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/structs/LaunchProjectData.sol";
import "../src/structs/LaunchFundingCyclesData.sol";
import "../src/structs/DeployMyDelegateData.sol";
import "./helpers/TestBaseWorkflowV3.sol";
import "@jbx-protocol/juice-delegates-registry/src/JBDelegatesRegistry.sol";

import {MyDelegate} from "../src/MyDelegate.sol";
import {MyDelegateProjectDeployer} from "../src/MyDelegateProjectDeployer.sol";
import {IJBDelegatesRegistry} from "@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {JBGlobalFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {MyDelegateDeployer} from "./../src/MyDelegateDeployer.sol";

// Inherits from "./helpers/TestBaseWorkflowV3.sol", called by super.setUp()
contract MyDelegateTest_Int is TestBaseWorkflowV3 {
    using JBFundingCycleMetadataResolver for JBFundingCycle;

    // Project setup params
    JBProjectMetadata _projectMetadata;
    JBFundingCycleData _data;
    JBFundingCycleMetadata _metadata;
    JBFundAccessConstraints[] _fundAccessConstraints; // Default empty
    IJBPaymentTerminal[] _terminals; // Default empty

    // Delegate setup params
    JBDelegatesRegistry delegatesRegistry;
    MyDelegate _delegateImpl;
    MyDelegateDeployer _delegateDepl;
    DeployMyDelegateData delegateData;
    MyDelegateProjectDeployer projectDepl;

    // Assigned when project is launched
    uint256 _projectId;

    // Used in JBFundingCycleMetadata
    uint256 reservedRate = 4500;

    // Used in JBFundingCycleData
    uint256 weight = 10 ** 18; // Minting 1 token per eth

    function setUp() public override {
        // Provides us with _jbOperatorStore and _jbETHPaymentTerminal
        super.setUp();

        /* 
        This setup follows a DelegateProjectDeployer pattern like in https://docs.juicebox.money/dev/extensions/juice-721-delegate/
        It deploys a new JB project and funding cycle, and then attaches our delegate to that funding cycle as a DataSource and Delegate.
        */

        // Placeholder project metadata, would customize this in prod.
        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});

        // https://docs.juicebox.money/dev/extensions/juice-delegates-registry/jbdelegatesregistry/
        delegatesRegistry = new JBDelegatesRegistry(IJBDelegatesRegistry(address(0)));

        // Instance of our delegate code
        _delegateImpl = new MyDelegate();

        // Required for our custom project deployer below, eventually attaches the delegate to the funding cycle.
        _delegateDepl = new MyDelegateDeployer(_delegateImpl, delegatesRegistry);

        // Custom deployer
        projectDepl = new MyDelegateProjectDeployer(_delegateDepl, _jbOperatorStore);


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
            dataSource: address(0),
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

        // Our delegate adds an allowlist functionality, create a mock list of one address for testing.
        address[] memory aList = new address[](1);
        aList[0] = address(123);

        // The imported struct used by our delegate
        delegateData = DeployMyDelegateData({
            allowList: aList
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
        _projectId = projectDepl.launchProjectFor(
            address(123),
            delegateData,
            launchProjectData,
            _jbController
        );

    }

    function testFail_PaymentFromUnAllowed() public {
        vm.deal(address(124), 1 ether);
        vm.prank(address(124));
        _jbETHPaymentTerminal.pay{value: 1 ether}(
            1,
            0,
            address(0),
            _beneficiary,
            /* _minReturnedTokens */
            0,
            /* _preferClaimedTokens */
            false,
            /* _memo */
            "Take my money!",
            /* _delegateMetadata */
            ""
        );

    }

    /* 
    function pay(
    uint256 _projectId,
    uint256 _amount,
    address _token,
    address _beneficiary,
    uint256 _minReturnedTokens,
    bool _preferClaimedTokens,
    string calldata _memo,
    bytes calldata _metadata
    )
    */

    function test_PaymentFromAllowed() public {
        emit log_uint(address(_jbETHPaymentTerminal).balance);

        bytes memory metadata = abi.encode(new bytes(0), new bytes(0), 1 ether);

        vm.deal(address(123), 1 ether);
        vm.prank(address(123));
        _jbETHPaymentTerminal.pay{value: 1 ether}(
            1,
            1 ether,
            address(0),
            _beneficiary,
            /* _minReturnedTokens */
            0,
            /* _preferClaimedTokens */
            true,
            /* _memo */
            "Take my money!",
            /* _delegateMetadata */
            metadata
        );

        emit log_uint(address(_jbETHPaymentTerminal).balance);
        emit log_uint(address(0xCDfc4483dfC62f9072de6b740b996EB0E295A467).balance);

    }

}
