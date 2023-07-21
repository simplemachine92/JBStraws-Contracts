// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


interface IJBStrawsDelegate {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Split(uint256 split);

    struct DeployJBStrawsData {
        address initialOwner;
        bytes32 allowedRoot;
    }

    struct JBDidPayData3_1_1 {
        address payer;
        uint256 projectId;
        uint256 currentFundingCycleConfiguration;
        JBTokenAmount amount;
        JBTokenAmount forwardedAmount;
        uint256 projectTokenCount;
        address beneficiary;
        bool preferClaimedTokens;
        string memo;
        bytes dataSourceMetadata;
        bytes payerMetadata;
    }

    struct JBDidRedeemData3_1_1 {
        address holder;
        uint256 projectId;
        uint256 currentFundingCycleConfiguration;
        uint256 projectTokenCount;
        JBTokenAmount reclaimedAmount;
        JBTokenAmount forwardedAmount;
        address beneficiary;
        string memo;
        bytes dataSourceMetadata;
        bytes redeemerMetadata;
    }

    struct JBPayDelegateAllocation3_1_1 {
        address delegate;
        uint256 amount;
        bytes metadata;
    }

    struct JBPayParamsData {
        address terminal;
        address payer;
        JBTokenAmount amount;
        uint256 projectId;
        uint256 currentFundingCycleConfiguration;
        address beneficiary;
        uint256 weight;
        uint256 reservedRate;
        string memo;
        bytes metadata;
    }

    struct JBRedeemParamsData {
        address terminal;
        address holder;
        uint256 projectId;
        uint256 currentFundingCycleConfiguration;
        uint256 tokenCount;
        uint256 totalSupply;
        uint256 overflow;
        JBTokenAmount reclaimAmount;
        bool useTotalOverflow;
        uint256 redemptionRate;
        string memo;
        bytes metadata;
    }

    struct JBRedemptionDelegateAllocation3_1_1 {
        address delegate;
        uint256 amount;
        bytes metadata;
    }

    struct JBTokenAmount {
        address token;
        uint256 value;
        uint256 decimals;
        uint256 currency;
    }

    function didPay(JBDidPayData3_1_1 memory _data) external payable;
    function didRedeem(JBDidRedeemData3_1_1 memory _data) external payable;
    function directory() external view returns (address);
    function initialize(uint256 _projectId, address _directory, DeployJBStrawsData memory _deployJBStrawsData)
        external;
    function owner() external view returns (address);
    function payRoot() external view returns (bytes32);
    function redeemRoot() external view returns (bytes32);
    function payWhitelistEnabled() external view returns (bool);
    function redeemWhitelistEnabled() external view returns (bool);
    function payParams(JBPayParamsData memory _data)
        external
        view
        returns (uint256 weight, string memory memo, JBPayDelegateAllocation3_1_1[] memory delegateAllocations);
    function projectId() external view returns (uint256);
    function verify(bytes32[] memory proof, bool isPayProof, address addr) external view returns (bool);
    function redeemParams(JBRedeemParamsData memory _data)
        external
        view
        returns (
            uint256 reclaimAmount,
            string memory memo,
            JBRedemptionDelegateAllocation3_1_1[] memory delegateAllocations
        );
    function renounceOwnership() external;
    function setPayRoot(bytes32 _root) external;
    function setRedeemRoot(bytes32 _root) external;
    function togglePayWhitelistEnabled() external;
    function toggleRedeemWhitelistEnabled() external;
    function supportsInterface(bytes4 _interfaceId) external view returns (bool);
    function topContributors(uint256) external view returns (address);
    function transferOwnership(address newOwner) external;
}
