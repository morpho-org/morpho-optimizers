// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Morpho Rewards Distributor harnessed for verification.
contract RewardsDistributorHarness is Ownable {
    using SafeTransferLib for ERC20;

    /// STORAGE ///

    ERC20 public immutable MORPHO;
    bytes32 public currRoot;
    mapping(address => uint256) public claimed;

    /// EVENTS ///

    event RootUpdated(bytes32 newRoot);

    event MorphoWithdrawn(address to, uint256 amount);

    event RewardsClaimed(address account, uint256 amount);

    /// ERRORS ///

    error ProofInvalidOrExpired();

    error AlreadyClaimed();

    /// CONSTRUCTOR ///

    constructor(address _morpho) {
        MORPHO = ERC20(_morpho);
    }

    /// EXTERNAL ///

    function updateRoot(bytes32 _newRoot) external onlyOwner {
        currRoot = _newRoot;
        emit RootUpdated(_newRoot);
    }

    function withdrawMorphoTokens(address _to, uint256 _amount) external onlyOwner {
        uint256 morphoBalance = MORPHO.balanceOf(address(this));
        uint256 toWithdraw = morphoBalance < _amount ? morphoBalance : _amount;
        MORPHO.safeTransfer(_to, toWithdraw);
        emit MorphoWithdrawn(_to, toWithdraw);
    }

    function claim(
        address _account,
        uint256 _claimable,
        bytes32[] calldata _proof
    ) external {
        bytes32 candidateRoot = MerkleProof.processProof(
            _proof,
            keccak256(abi.encodePacked(_account, _claimable))
        );
        // HARNESS: removed prevRoot
        if (candidateRoot != currRoot) revert ProofInvalidOrExpired();

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
