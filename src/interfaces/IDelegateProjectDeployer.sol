// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IDelegateProjectDeployer {
    struct DeployMyDelegateData {
        address[] allowList;
    }

    struct JBFundAccessConstraints {
        address terminal;
        address token;
        uint256 distributionLimit;
        uint256 distributionLimitCurrency;
        uint256 overflowAllowance;
        uint256 overflowAllowanceCurrency;
    }

    struct JBFundingCycleData {
        uint256 duration;
        uint256 weight;
        uint256 discountRate;
        address ballot;
    }

    struct JBFundingCycleMetadata {
        JBGlobalFundingCycleMetadata global;
        uint256 reservedRate;
        uint256 redemptionRate;
        uint256 ballotRedemptionRate;
        bool pausePay;
        bool pauseDistributions;
        bool pauseRedeem;
        bool pauseBurn;
        bool allowMinting;
        bool allowTerminalMigration;
        bool allowControllerMigration;
        bool holdFees;
        bool preferClaimedTokenOverride;
        bool useTotalOverflowForRedemptions;
        bool useDataSourceForPay;
        bool useDataSourceForRedeem;
        address dataSource;
        uint256 metadata;
    }

    struct JBGlobalFundingCycleMetadata {
        bool allowSetTerminals;
        bool allowSetController;
        bool pauseTransfers;
    }

    struct JBGroupedSplits {
        uint256 group;
        JBSplit[] splits;
    }

    struct JBProjectMetadata {
        string content;
        uint256 domain;
    }

    struct JBSplit {
        bool preferClaimed;
        bool preferAddToBalance;
        uint256 percent;
        uint256 projectId;
        address beneficiary;
        uint256 lockedUntil;
        address allocator;
    }

    struct LaunchFundingCyclesData {
        JBFundingCycleData data;
        JBFundingCycleMetadata metadata;
        uint256 mustStartAtOrAfter;
        JBGroupedSplits[] groupedSplits;
        JBFundAccessConstraints[] fundAccessConstraints;
        address[] terminals;
        string memo;
    }

    struct LaunchProjectData {
        JBProjectMetadata projectMetadata;
        JBFundingCycleData data;
        JBFundingCycleMetadata metadata;
        uint256 mustStartAtOrAfter;
        JBGroupedSplits[] groupedSplits;
        JBFundAccessConstraints[] fundAccessConstraints;
        address[] terminals;
        string memo;
    }

    struct ReconfigureFundingCyclesData {
        JBFundingCycleData data;
        JBFundingCycleMetadata metadata;
        uint256 mustStartAtOrAfter;
        JBGroupedSplits[] groupedSplits;
        JBFundAccessConstraints[] fundAccessConstraints;
        string memo;
    }

    function delegateDeployer() external view returns (address);
    function launchFundingCyclesFor(
        uint256 _projectId,
        DeployMyDelegateData memory _deployMyDelegateData,
        LaunchFundingCyclesData memory _launchFundingCyclesData,
        address _controller
    ) external returns (uint256 configuration);
    function launchProjectFor(
        address _owner,
        DeployMyDelegateData memory _deployMyDelegateData,
        LaunchProjectData memory _launchProjectData,
        address _controller
    ) external returns (uint256 projectId);
    function operatorStore() external view returns (address);
    function reconfigureFundingCyclesOf(
        uint256 _projectId,
        DeployMyDelegateData memory _deployMyDelegateData,
        ReconfigureFundingCyclesData memory _reconfigureFundingCyclesData,
        address _controller
    ) external returns (uint256 configuration);
}