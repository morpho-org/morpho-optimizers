// SPDX-License-Identifier: AGPL-3.0-only
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

    ERC20 public immutable MORPHO;
    bytes32 public currRoot; // The merkle tree's root of the current rewards distribution.
    bytes32 public prevRoot; // The merkle tree's root of the previous rewards distribution.
    mapping(address => uint256) public claimed; // The rewards already claimed. account -> amount.

    /// EVENTS ///

    /// @notice Emitted when the root is updated.
    /// @param newRoot The new merkle's tree root.
    event RootUpdated(bytes32 newRoot);

    /// @notice Emitted when MORPHO tokens are withdrawn.
    /// @param to The address of the recipient.
    /// @param amount The amount of MORPHO tokens withdrawn.
    event MorphoWithdrawn(address to, uint256 amount);

    /// @notice Emitted when an account claims rewards.
    /// @param account The address of the claimer.
    /// @param amount The amount of rewards claimed.
    event RewardsClaimed(address account, uint256 amount);

    /// ERRORS ///

    /// @notice Thrown when the proof is invalid or expired.
    error ProofInvalidOrExpired();

    /// @notice Thrown when the claimer has already claimed the rewards.
    error AlreadyClaimed();

    /// CONSTRUCTOR ///

    /// @notice Constructs Morpho's RewardsDistributor contract.
    /// @param _morpho The address of the MORPHO token to distribute.
    constructor(address _morpho) {
        MORPHO = ERC20(_morpho);
    }

    /// EXTERNAL ///

    /// @notice Updates the current merkle tree's root.
    /// @param _newRoot The new merkle tree's root.
    function updateRoot(bytes32 _newRoot) external onlyOwner {
        prevRoot = currRoot;
        currRoot = _newRoot;
        emit RootUpdated(_newRoot);
    }

    /// @notice Withdraws MORPHO tokens to a recipient.
    /// @param _to The address of the recipient.
    /// @param _amount The amount of MORPHO tokens to transfer.
    function withdrawMorphoTokens(address _to, uint256 _amount) external onlyOwner {
        uint256 morphoBalance = MORPHO.balanceOf(address(this));
        uint256 toWithdraw = morphoBalance < _amount ? morphoBalance : _amount;
        MORPHO.safeTransfer(_to, toWithdraw);
        emit MorphoWithdrawn(_to, toWithdraw);
    }

    /// @notice Claims rewards.
    /// @param _account The address of the claimer.
    /// @param _claimable The overall claimable amount of token rewards.
    /// @param _proof The merkle proof that validates this claim.
    function claim(
        address _account,
        uint256 _claimable,
        bytes32[] calldata _proof
    ) external {
        bytes32 candidateRoot = MerkleProof.processProof(
            _proof,
            keccak256(abi.encodePacked(_account, _claimable))
        );
        if (candidateRoot != currRoot && candidateRoot != prevRoot) revert ProofInvalidOrExpired();

        uint256 alreadyClaimed = claimed[_account];
        if (_claimable <= alreadyClaimed) revert AlreadyClaimed();

        uint256 amount;
        unchecked {
            amount = _claimable - alreadyClaimed;
        }

        claimed[_account] = _claimable;

        MORPHO.safeTransfer(_account, amount);
        emit RewardsClaimed(_account, amount);
    }
}
