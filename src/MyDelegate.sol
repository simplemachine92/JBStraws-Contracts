// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {JBOperatable} from "@jbx-protocol/juice-contracts-v3/contracts/abstract/JBOperatable.sol";
import {JBStrawsOperations} from "./libraries/JBStrawsOperations.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import {IJBDirectory} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import {IJBPayDelegate3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayDelegate3_1_1.sol";
import {IJBRedemptionDelegate3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBRedemptionDelegate3_1_1.sol";
import {IJBFundingCycleDataSource3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleDataSource3_1_1.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";

import {JBPayParamsData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayParamsData.sol";
import {JBDidPayData3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidPayData3_1_1.sol";
import {JBDidRedeemData3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidRedeemData3_1_1.sol";
import {JBRedeemParamsData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedeemParamsData.sol";
import {JBPayDelegateAllocation3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayDelegateAllocation3_1_1.sol";
import {JBRedemptionDelegateAllocation3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedemptionDelegateAllocation3_1_1.sol";
import {DeployMyDelegateData} from "./structs/DeployMyDelegateData.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @notice A Data Source contract that utilizes Merkle Proofs to act as an efficient whitelist mechanism for JB projects.
contract MyDelegate is JBOperatable, IJBFundingCycleDataSource3_1_1 {
    bool public payWhitelistEnabled;
    bool public redeemWhitelistEnabled;
    bytes32 public payRoot;
    bytes32 public redeemRoot;

    /// @notice The Juicebox project ID this contract's functionality applies to sometimes referred to as "domain".
    uint256 public projectId;

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory public directory;
    IJBController3_1 private _controller;

    constructor(IJBOperatorStore _operatorStore) JBOperatable(_operatorStore) {}

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param _interfaceId The ID of the interface to check for adherence to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return _interfaceId == type(IJBFundingCycleDataSource3_1_1).interfaceId
            || _interfaceId == type(IJBPayDelegate3_1_1).interfaceId || _interfaceId == type(IJBRedemptionDelegate3_1_1).interfaceId;
    }

    /// @notice Initializes the clone contract with project details and a directory from which ecosystem payment terminals and controller can be found.
    /// @param _projectId The ID of the project this contract's functionality applies to.
    /// @param _directory The directory of terminals and controllers for projects.
    /// @param _deployMyDelegateData Data necessary to deploy the delegate.
    function initialize(uint256 _projectId, IJBDirectory _directory, DeployMyDelegateData memory _deployMyDelegateData, IJBController3_1 controller)
        external
    {
        // Stop re-initialization.
        if (projectId != 0) revert();

        // Store the basics.
        projectId = _projectId;
        directory = _directory;

        payRoot = _deployMyDelegateData.initPayRoot;
        redeemRoot = _deployMyDelegateData.initRedeemRoot;

        payWhitelistEnabled =_deployMyDelegateData.initPayWL;
        redeemWhitelistEnabled = _deployMyDelegateData.initRedeemWL;

        _controller = controller;
    }

    /// @notice This function gets called when the project receives a payment.
    /// @dev Part of IJBFundingCycleDataSource.
    /// @dev This implementation just sets this contract up to receive a `didPay` call.
    /// @param _data The Juicebox standard project payment data. See https://docs.juicebox.money/dev/api/data-structures/jbpayparamsdata/.
    /// @return weight The weight that project tokens should get minted relative to. This is useful for optionally customizing how many tokens are issued per payment.
    /// @return memo A memo to be forwarded to the event. Useful for describing any new actions that are being taken.
    /// @return delegateAllocations Amount to be sent to delegates instead of adding to local balance. Useful for auto-routing funds from a treasury as payment come in.
    function payParams(JBPayParamsData calldata _data)
        external
        view
        virtual
        override
        returns (uint256 weight, string memory memo, JBPayDelegateAllocation3_1_1[] memory delegateAllocations)
    {
        bytes32[] memory proof = abi.decode(_data.metadata, (bytes32[]));

        // Get original tx sender to check whitelist.
        address payer = _data.payer;

        if (payWhitelistEnabled) {
        // Verify whitelisting proof and continue, or revert.
        verify(proof, true, payer);
        }
        
        // Forward the default weight received from the protocol.
        weight = _data.weight;
        // Forward the default memo received from the payer.
        memo = _data.memo;
    }

    /// @notice This function gets called when the project's token holders redeem.
    /// @dev Part of IJBFundingCycleDataSource.
    /// @param _data Standard Juicebox project redemption data. See https://docs.juicebox.money/dev/api/data-structures/jbredeemparamsdata/.
    /// @return reclaimAmount Amount to be reclaimed from the treasury. This is useful for optionally customizing how much funds from the treasury are dispursed per redemption.
    /// @return memo A memo to be forwarded to the event. Useful for describing any new actions are being taken.
    /// @return delegateAllocations Amount to be sent to delegates instead of being added to the beneficiary. Useful for auto-routing funds from a treasury as redemptions are sought.
    function redeemParams(JBRedeemParamsData calldata _data)
        external
        view
        virtual
        override
        returns (uint256 reclaimAmount, string memory memo, JBRedemptionDelegateAllocation3_1_1[] memory delegateAllocations)
    {
        bytes32[] memory proof = abi.decode(_data.metadata, (bytes32[]));

        // Get original tx sender to check whitelist.
        address holder = _data.holder;
        
        if (redeemWhitelistEnabled == true) {
        // Verify whitelisting proof and continue, or revert.
        verify(proof, false, holder);
        }

        // Forward the default reclaimAmount received from the protocol.
        reclaimAmount = _data.reclaimAmount.value;
        // Forward the default memo received from the redeemer.
        memo = _data.memo;
    }

    function setPayRoot(bytes32 _root)
        external requirePermission(_controller.projects().ownerOf(projectId), projectId, JBStrawsOperations.WL_ADMIN)
    {
        payRoot = _root;
    }

    function setRedeemRoot(bytes32 _root)
        external requirePermission(_controller.projects().ownerOf(projectId), projectId, JBStrawsOperations.WL_ADMIN)
    {
        redeemRoot = _root;
    }

    function togglePayWhitelistEnabled()
        external requirePermission(_controller.projects().ownerOf(projectId), projectId, JBStrawsOperations.WL_ADMIN)
    {
        payWhitelistEnabled = !payWhitelistEnabled;
    }

    function toggleRedeemWhitelistEnabled()
        external requirePermission(_controller.projects().ownerOf(projectId), projectId, JBStrawsOperations.WL_ADMIN)
    {
        redeemWhitelistEnabled = !redeemWhitelistEnabled;
    }

    function verify(
        bytes32[] memory proof,
        bool isPayProof,
        address addr
    ) public view returns (bool) {
        bytes32 leaf = bytes32(uint256(uint160(addr)));

        isPayProof? require(MerkleProof.verify(proof, payRoot, leaf), "Not In Allow List")
        : require(MerkleProof.verify(proof, redeemRoot, leaf), "Not In Allow List");
        
        return true;
    }

}
