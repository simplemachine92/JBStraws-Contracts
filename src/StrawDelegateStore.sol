// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract StrawDelegateStore {
    bytes32 private root;

    constructor(bytes32 _root) {
        root = _root;
    }

    function verify(
        bytes32[] memory proof,
        address addr
    ) external view returns (bool) {
        // (2)
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(addr))));
        // (3)
        require(MerkleProof.verify(proof, root, leaf), "Invalid proof");
        // (4)
        return true;
    }
}