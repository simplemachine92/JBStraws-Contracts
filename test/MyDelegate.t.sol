// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {MyDelegate} from "../src/MyDelegate.sol";
import {MyDelegateProjectDeployer} from "../src/MyDelegateProjectDeployer.sol";
import {IJBDelegatesRegistry} from "@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol";
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {JBGlobalFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {MyDelegateDeployer} from "./../src/MyDelegateDeployer.sol";
import {IDelegateProjectDeployer} from "../src/interfaces/IDelegateProjectDeployer.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import "@jbx-protocol/juice-delegates-registry/src/JBDelegatesRegistry.sol";
import "@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../src/structs/LaunchProjectData.sol";
import "../src/structs/LaunchFundingCyclesData.sol";
import "../src/structs/DeployMyDelegateData.sol";
import "./helpers/TestBaseWorkflowV3.sol";

contract MyDelegateTest_Unit is TestBaseWorkflowV3 {
    using stdStorage for StdStorage;
    using JBFundingCycleMetadataResolver for JBFundingCycle;

    JBProjectMetadata _projectMetadata;
    JBFundingCycleData _data;
    JBFundingCycleData _dataReconfiguration;
    JBFundingCycleData _dataWithoutBallot;
    JBFundingCycleMetadata _metadata;
    JBFundAccessConstraints[] _fundAccessConstraints; // Default empty
    IJBPaymentTerminal[] _terminals; // Default empty
    MyDelegate _delegateImpl;
    MyDelegateDeployer _delegateDepl;
    JBDelegatesRegistry delegatesRegistry;
    DeployMyDelegateData delegateData;
    MyDelegateProjectDeployer projectDepl;

    uint256 _projectId;
    uint256 reservedRate = 4500;
    uint256 weight = 10 ** 18; // Minting 1 token per eth

    function setUp() public override {
        super.setUp();

        delegatesRegistry = new JBDelegatesRegistry(IJBDelegatesRegistry(address(0)));

        _delegateImpl = new MyDelegate();

        _delegateDepl = new MyDelegateDeployer(_delegateImpl, delegatesRegistry);

        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});

        projectDepl = new MyDelegateProjectDeployer(_delegateDepl, _jbOperatorStore);

        _data = JBFundingCycleData({
            duration: 6 days,
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

        _terminals = [_jbETHPaymentTerminal];

        JBGroupedSplits[] memory _groupedSplits = new JBGroupedSplits[](1); // Default empty

        address[] memory aList = new address[](1);
        aList[0] = address(123);

        delegateData = DeployMyDelegateData({
            allowList: aList
        });

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

        _projectId = projectDepl.launchProjectFor(
            address(123),
            delegateData,
            launchProjectData,
            _jbController
        );

    }

    function testLaunchProject() public {
        emit log_uint(_projectId);

        vm.deal(address(123), 2 ether);
        vm.deal(address(124), 2 ether);
        vm.prank(address(123));
        _jbETHPaymentTerminal.pay{value: 1 ether}(
            1,
            1,
            address(0),
            address(123),
            /* _minReturnedTokens */
            1,
            /* _preferClaimedTokens */
            false,
            /* _memo */
            "Take my money!",
            /* _delegateMetadata */
            ""
        );

    }
}
