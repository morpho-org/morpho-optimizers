// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Morpho Rewards Distributor.
/// @notice This contract allows Morpho users to claim their rewards. This contract is largely innspired by Euler Distributor's contract: https://github.com/euler-xyz/euler-contracts/blob/master/contracts/mining/EulDistributor.sol.
contract RewardsDistributor is Ownable {
    using SafeTransferLib for ERC20;

    /// STORAGE ///

    bytes32 public currRoot; // The merkle tree's root of the current rewards distribution.
    bytes32 public prevRoot; // The merkle tree's root of the previous rewards distribution.
    mapping(address => mapping(address => uint256)) public claimed; // The rewards already claimed. account -> token -> amount

    /// EXTERNAL ///

    /// @notice Updates the current merkle tree's root.
    /// @param _newRoot The new merkle's tree root.
    function updateRoot(bytes32 _newRoot) external onlyOwner {
        prevRoot = currRoot;
        currRoot = _newRoot;
    }

    /// @notice Claims rewards.
    /// @param _account The address of the receiver.
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
        ); // 72 bytes leaf.
        require(candidateRoot == currRoot || candidateRoot == prevRoot, "proof invalid/expired");

        uint256 alreadyClaimed = claimed[_account][_token];
        require(_claimable > alreadyClaimed, "already claimed");

        uint256 amount;
        unchecked {
            amount = _claimable - alreadyClaimed;
        }

        claimed[_account][_token] = _claimable;

        ERC20(_token).safeTransfer(_account, amount);
    }
}
