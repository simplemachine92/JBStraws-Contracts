// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import {IJBDelegatesRegistry} from "@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol";
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import {MyDelegate} from "./../src/MyDelegate.sol";
import {MyDelegateDeployer} from "./../src/MyDelegateDeployer.sol";
import {MyDelegateProjectDeployer} from "./../src/MyDelegateProjectDeployer.sol";
import {Merkle} from "murky/Merkle.sol";

import "../src/structs/LaunchProjectData.sol";
import "../src/structs/LaunchFundingCyclesData.sol";
import "../src/structs/DeployMyDelegateData.sol";
import "@jbx-protocol/juice-delegates-registry/src/JBDelegatesRegistry.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/JBController3_1.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/JBETHPaymentTerminal3_1_1.sol";
import "@paulrberg/contracts/math/PRBMath.sol";

import {MyDelegate} from "../src/MyDelegate.sol";
import {MyDelegateProjectDeployer} from "../src/MyDelegateProjectDeployer.sol";
import {IJBDelegatesRegistry} from "@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {JBGlobalFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {IStrawDelegate} from "../src/interfaces/IStrawDelegate.sol";

import "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBCurrencies.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBConstants.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol";

contract AccessJBLib {
    function ETH() external pure returns (uint256) {
        return JBCurrencies.ETH;
    }

    function USD() external pure returns (uint256) {
        return JBCurrencies.USD;
    }

    function ETHToken() external pure returns (address) {
        return JBTokens.ETH;
    }

    function MAX_FEE() external pure returns (uint256) {
        return JBConstants.MAX_FEE;
    }

    function SPLITS_TOTAL_PERCENT() external pure returns (uint256) {
        return JBConstants.SPLITS_TOTAL_PERCENT;
    }
}

abstract contract Deploy is Script, Test {

    // Project setup params
    JBProjectMetadata _projectMetadata;
    JBFundingCycleData _data;
    JBFundingCycleMetadata _metadata;
    JBFundAccessConstraints[] _fundAccessConstraints; // Default empty
    JBETHPaymentTerminal3_1_1 _jbETHPaymentTerminal = JBETHPaymentTerminal3_1_1(0x82129d4109625F94582bDdF6101a8Cd1a27919f5);
    JBController3_1 _jbController = JBController3_1(0x1d260DE91233e650F136Bf35f8A4ea1F2b68aDB6);
    IStrawDelegate _straws;
    Merkle _m;
    AccessJBLib internal _accessJBLib;

    // Delegate setup params
    JBDelegatesRegistry delegatesRegistry;
    MyDelegate _delegateImpl;
    MyDelegateDeployer _delegateDepl;
    DeployMyDelegateData delegateData;
    MyDelegateProjectDeployer projectDepl;

    IJBPaymentTerminal[] _terminals; // Default empty

    // Assigned when project is launched
    uint256 _projectId;

    // Used in JBFundingCycleMetadata, 4500 = 45% I believe, but using 0 for testing calcs
    uint256 reservedRate = 0;

    // Used in JBFundingCycleData
    uint256 weight = 10 ** 18; // Minting 1 token per eth

    bytes32 tRoot = 0xa9273ce1e6b4ac4eb3d07f01103d44e3778747536780332f977c5915415fd7db;
    bytes32 tRoot2 = 0x93514c6c0f9d7e0d68fd8c122c90ce816eb10b5b6949adb36079c89d4cf3c49a;

    function _run(IJBOperatorStore _operatorStore, IJBDelegatesRegistry _registry) internal {
        // jbethpaymentterminal mainnet: 0xfa391de95fcbcd3157268b91d8c7af083e607a5c
        // jbcontroller mainnet: 0x97a5b9D9F0F7cD676B69f584F29048D0Ef4BB59b

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

         // AccessJBLib
        _accessJBLib = new AccessJBLib();

        MyDelegate _delegateImplementation = new MyDelegate(_operatorStore);
        MyDelegateDeployer _delegateDeployer = new MyDelegateDeployer(_delegateImplementation, _registry);
        projectDepl = new MyDelegateProjectDeployer(
              _delegateDeployer,
              _operatorStore
            );

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
            dataSource: address(_delegateImplementation),
            metadata: 0
        });

        _fundAccessConstraints.push(
            JBFundAccessConstraints({
                terminal: _jbETHPaymentTerminal,
                token: _accessJBLib.ETHToken(),
                distributionLimit: 2 ether,
                overflowAllowance: type(uint232).max,
                distributionLimitCurrency: 1, // Currency = ETH
                overflowAllowanceCurrency: 1
            })
        );

        // Imported from TestBaseWorkflowV3.sol via super.setUp() https://docs.juicebox.money/dev/learn/architecture/terminals/
        _terminals = [_jbETHPaymentTerminal];

        JBGroupedSplits[] memory _groupedSplits = new JBGroupedSplits[](1); // Default empty

        /* struct DeployMyDelegateData {
        bytes32 initPayRoot;
        bytes32 initRedeemRoot;
        bool initPayWL;
        bool initRedeemWL;
        } */

        // The imported struct used by our delegate
        delegateData = DeployMyDelegateData({
            initPayRoot: tRoot,
            initRedeemRoot: tRoot2,
            initPayWL: true,
            initRedeemWL: true
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
            address(0x55A178b6AfB3879F4a16c239A9F528663e7d76b3),
            delegateData,
            launchProjectData,
            _jbController
        );

        vm.stopBroadcast();

        (, JBFundingCycleMetadata memory metadata, ) = _jbController.latestConfiguredFundingCycleOf(_projectId);


        emit log_uint(_projectId);
        emit log_address(metadata.dataSource);
    }
}

contract DeployMainnet is Deploy {
    IJBOperatorStore _operatorStore = IJBOperatorStore(0x6F3C5afCa0c9eDf3926eF2dDF17c8ae6391afEfb);
    IJBDelegatesRegistry _registry = IJBDelegatesRegistry(0x33265D9eaD1291FAA981a177278dF8053aF24221);

    function run() public {
        _run(_operatorStore, _registry);
    }
}

contract DeployFork is Deploy {
    IJBOperatorStore _operatorStore = IJBOperatorStore(0x6F3C5afCa0c9eDf3926eF2dDF17c8ae6391afEfb);
    IJBDelegatesRegistry _registry = IJBDelegatesRegistry(0x33265D9eaD1291FAA981a177278dF8053aF24221);

    function run() public {
        _run(_operatorStore, _registry);
    }
}

contract DeployGoerli is Deploy {
    IJBOperatorStore _operatorStore = IJBOperatorStore(0x99dB6b517683237dE9C494bbd17861f3608F3585);
    IJBDelegatesRegistry _registry = IJBDelegatesRegistry(0x4BdB4170056dd9530747D9B3338D75f4535eBcDB);

    function setUp() public {}

    function run() public {
        _run(_operatorStore, _registry);
    }
}