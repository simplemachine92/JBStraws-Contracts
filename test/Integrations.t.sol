// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/structs/LaunchProjectData.sol";
import "../src/structs/LaunchFundingCyclesData.sol";
import "../src/structs/DeployMyDelegateData.sol";
import "./helpers/TestBaseWorkflowV3.sol";
import "@jbx-protocol/juice-delegates-registry/src/JBDelegatesRegistry.sol";
import "@paulrberg/contracts/math/PRBMath.sol";

import {MyDelegate} from "../src/MyDelegate.sol";
import {MyDelegateProjectDeployer} from "../src/MyDelegateProjectDeployer.sol";
import {IJBDelegatesRegistry} from "@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {JBGlobalFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {MyDelegateDeployer} from "./../src/MyDelegateDeployer.sol";
import {ContributorSplitData} from "../src/structs/ContributorSplitData.sol";

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

    // Used in JBFundingCycleMetadata, 4500 = 45% I believe, but using 0 for testing calcs
    uint256 reservedRate = 0;

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

        // Our delegate adds a top contributor donation option, create a mock list of one address for testing.
        address[] memory aList = new address[](4);
        aList[0] = address(123);
        aList[1] = address(1234);
        aList[2] = address(12345);
        aList[3] = address(123456);

        // The imported struct used by our delegate
        delegateData = DeployMyDelegateData({
            topContributorList: aList
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

    function test_PaymentForAllContributorsSplit() public {
        address[] memory aList = new address[](4);
        aList[0] = address(123);
        aList[1] = address(1234);
        aList[2] = address(12345);
        aList[3] = address(123456);

        ContributorSplitData memory splitCallData = ContributorSplitData({
            donateToContributors: true,
            disperseToAll: true,
            bpToDisperse: 2500,
            selectedContributors: aList
        });

        // The last uint in this data denotes how much to distribute to the top contributors.
        bytes memory metadata = abi.encode(splitCallData);

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
            false,
            /* _memo */
            "Take my money!",
            /* _delegateMetadata */
            metadata
        );

        uint256 distAmount = PRBMath.mulDiv(1 ether, 2500, 10000);

        // Check that ETH payment was split correctly between terminal and delegate
        assertEq(address(_jbETHPaymentTerminal).balance, .75 ether);
        
        // Check if contributors received eth
        assertEq(address(1234).balance, (distAmount / aList.length));
    }

    function testFuzz_PaymentForAllContributorsSplit(uint128 amount) public {
        // Assumes nobody can access more than 340282366920938463463.374607431768211455 ether

        address[] memory aList = new address[](4);
        aList[0] = address(123);
        aList[1] = address(1234);
        aList[2] = address(12345);
        aList[3] = address(123456);

        ContributorSplitData memory splitCallData = ContributorSplitData({
            donateToContributors: true,
            disperseToAll: true,
            bpToDisperse: 2500,
            selectedContributors: aList
        });

        // The last uint in this data denotes how much to distribute to the top contributors.
        bytes memory metadata = abi.encode(splitCallData);

        vm.deal(address(123), amount);
        vm.prank(address(123));
        _jbETHPaymentTerminal.pay{value: amount}(
            1,
            amount,
            address(0),
            _beneficiary,
            /* _minReturnedTokens */
            0,
            /* _preferClaimedTokens */
            false,
            /* _memo */
            "Take my money!",
            /* _delegateMetadata */
            metadata
        );

        uint256 distAmount = PRBMath.mulDiv(amount, 2500, 10000);

        // Check that ETH payment was split correctly between terminal and delegate
        assertEq(address(_jbETHPaymentTerminal).balance, (amount - distAmount));

        // Check if contributors received eth
        assertEq(address(1234).balance, (distAmount / aList.length));
    }

    function test_PaymentForSelectContributorsAddressSplit() public {
        // Just a few addresses this time
        address[] memory aList = new address[](2);
        aList[0] = address(123);
        aList[1] = address(1234);

        ContributorSplitData memory splitCallData = ContributorSplitData({
            donateToContributors: true,
            disperseToAll: false,
            bpToDisperse: 5000,
            selectedContributors: aList
        });

        // The last uint in this data denotes how much to distribute to the top contributors.
        bytes memory metadata = abi.encode(splitCallData);

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
            false,
            /* _memo */
            "Take my money!",
            /* _delegateMetadata */
            metadata
        );

        uint256 distAmount = PRBMath.mulDiv(1 ether, 5000, 10000);

        // Check that ETH payment was split correctly between terminal and delegate
        assertEq(address(_jbETHPaymentTerminal).balance, .5 ether);
        
        // Check if contributors received eth
        assertEq(address(1234).balance, (distAmount / aList.length));
    }

    function testFuzz_PaymentForSelectContributorsAddressSplit(uint128 amount, uint16 bp) public {
        vm.assume(bp <= 10000 && bp >= 1000);
        vm.assume(amount >= 1 ether && amount <= 10 ether);

        // Just a few addresses this time
        address[] memory aList = new address[](2);
        aList[0] = address(123);
        aList[1] = address(1234);

        ContributorSplitData memory splitCallData = ContributorSplitData({
            donateToContributors: true,
            disperseToAll: false,
            bpToDisperse: bp,
            selectedContributors: aList
        });

        bytes memory metadata = abi.encode(splitCallData);

        vm.deal(address(123), amount);
        vm.prank(address(123));
        _jbETHPaymentTerminal.pay{value: amount}(
            1,
            amount,
            address(0),
            _beneficiary,
            /* _minReturnedTokens */
            0,
            /* _preferClaimedTokens */
            false,
            /* _memo */
            "Take my money!",
            /* _delegateMetadata */
            metadata
        );

        uint256 distAmount = PRBMath.mulDiv(amount, bp, 10000);

        // Check that ETH payment was split correctly between terminal and delegate
        assertEq(address(_jbETHPaymentTerminal).balance, amount - distAmount);
        
        // Check if contributors received eth
        assertEq(address(1234).balance, (distAmount / aList.length));
    }

    function testFail_PaymentForInvalidContributorsAddressSplit() public {
        address[] memory aList = new address[](4);
        aList[0] = address(129);
        aList[1] = address(1236);
        aList[2] = address(12344);
        aList[3] = address(123455);

        ContributorSplitData memory splitCallData = ContributorSplitData({
            donateToContributors: true,
            disperseToAll: true,
            bpToDisperse: 2500,
            selectedContributors: aList
        });

        // The last uint in this data denotes how much to distribute to the top contributors.
        bytes memory metadata = abi.encode(splitCallData);

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
            false,
            /* _memo */
            "Take my money!",
            /* _delegateMetadata */
            metadata
        );

        uint256 distAmount = PRBMath.mulDiv(1 ether, 2500, 10000);

        // Check that ETH payment was split correctly between terminal and delegate
        assertEq(address(_jbETHPaymentTerminal).balance, .75 ether);
        
        // Check if contributors received eth
        assertEq(address(1234).balance, (distAmount / aList.length));
    }

}
