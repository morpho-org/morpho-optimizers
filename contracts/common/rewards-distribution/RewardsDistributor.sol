// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Morpho Rewards Distributor.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice This contract allows Morpho users to claim their rewards. This contract is largely inspired by Euler Distributor's contract: https://github.com/euler-xyz/euler-contracts/blob/master/contracts/mining/EulDistributor.sol.
contract RewardsDistributor is Ownable {
    using SafeTransferLib for ERC20;

    /// STORAGE ///

    bytes32 public currRoot; // The merkle tree's root of the current rewards distribution.
    bytes32 public prevRoot; // The merkle tree's root of the previous rewards distribution.
    mapping(address => mapping(address => uint256)) public claimed; // The rewards already claimed. account -> token -> amount.

    /// EVENTS ///

    /// @notice Emitted when the root is updated.
    /// @param _newRoot The new merkle's tree root.
    event RootUpdated(bytes32 _newRoot);

    /// @notice Emitted when an account claims rewards.
    /// @param _account The address of the claimer.
    /// @param _amountClaimed The amount of rewards claimed.
    event RewardsClaimed(address _account, uint256 _amountClaimed);

    /// ERRORS ///

    /// @notice Thrown when the proof is invalid or expired.
    error ProofInvalidOrExpired();

    /// @notice Thrown when the claimer has already claimed the rewards.
    error AlreadyClaimed();

    /// EXTERNAL ///

    /// @notice Updates the current merkle tree's root.
    /// @param _newRoot The new merkle tree's root.
    function updateRoot(bytes32 _newRoot) external onlyOwner {
        prevRoot = currRoot;
        currRoot = _newRoot;
        emit RootUpdated(_newRoot);
    }

    /// @notice Claims rewards.
    /// @param _account The address of the claimer.
    /// @param _token The address of token being claimed (ie MORPHO).
    /// @param _claimable The overall claimable amount of token rewards.
    /// @param _proof The merkle proof that validates this claim.
    function claim(
        address _account,
        address _token,
        uint256 _claimable,
        bytes32[] calldata _proof
    ) external {
        bytes32 candidateRoot = MerkleProof.processProof(
            _proof,
            keccak256(abi.encodePacked(_account, _token, _claimable))
        );
        if (candidateRoot != currRoot && candidateRoot != prevRoot) revert ProofInvalidOrExpired();

        uint256 alreadyClaimed = claimed[_account][_token];
        if (_claimable <= alreadyClaimed) revert AlreadyClaimed();

        uint256 amount;
        unchecked {
            amount = _claimable - alreadyClaimed;
        }

        claimed[_account][_token] = _claimable;

        ERC20(_token).safeTransfer(_account, amount);
        emit RewardsClaimed(_account, amount);
    }
}
