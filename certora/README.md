This folder contains the verification of the rewards distribution mechanism of Morpho Optimizers using CVL, Certora's Verification Language.

# Folder and file structure

The [`certora/specs`](specs) folder contains the specification files.

The [`certora/confs`](confs) folder contains a configuration file for each corresponding specification file.

The [`certora/helpers`](helpers) folder contains files that enable the verification of Morpho Blue.

# Overview of the verification

This work aims at providing a formally verified rewards checker.
The rewards checker is composed of the [Checker.sol](checker/Checker.sol) file, which takes a certificate as an input.
The certificate is assumed to contain the submitted root to verify, a total amount of rewards distributed, and a Merkle tree, and it is checked that:

1. the Merkle tree is a well-formed Merkle tree
2. the total amount of rewards distributed matches the total rewards contained in the Merkle tree

Those checks are done by only using "trusted" functions, namely `newLeaf` and `newInternalNode`, that have been formally verified to preserve those invariants:

- it is checked in [MerkleTrees.spec](specs/MerkleTrees.spec) that those functions lead to creating well-formed trees.
  Well-formed trees also verify that the value of their internal node is the sum of the rewards it contains.
- it is checked in [RewardsDistributor.spec](specs/RewardsDistributor.spec) that the rewards distributor is correct, meaning that claimed rewards correspond exactly to the rewards contained in the corresponding Merkle tree.

# Getting started

## Verifying the rewards checker

Install `certora-cli` package with `pip install certora-cli`.
To verify specification files, pass to `certoraRun` the corresponding configuration file in the [`certora/confs`](confs) folder.
It requires having set the `CERTORAKEY` environment variable to a valid Certora key.
You can also pass additional arguments, notably to verify a specific rule.
For example, at the root of the repository:

```
certoraRun certora/confs/MerkleTrees.conf --rule wellFormed
```

## Running the rewards checker

To verify that a given list of proofs corresponds to a valid Merkle tree, you must generate a certificate from it.
Examples of lists of proofs can be found as `proofs.json` files in the subfolders of the [distribution folder of morpho-optimizers-rewards](https://github.com/morpho-org/morpho-optimizers-rewards/tree/main/distribution).
This assumes that the list of proofs is in the expected JSON format.
For example, at the root of the repository, given a `proofs.json` file:

```
python certora/checker/create_certificate.py proofs.json
```

This requires installing the corresponding libraries first:

```
pip install web3 eth-tester py-evm
```

Then, check this certificate:

```
FOUNDRY_PROFILE=checker forge test
```
