This folder contains the verification of the rewards distribution mechanism of Morpho Optimizers using CVL, Certora's Verification Language.

# Folder and file structure

The [`certora/specs`](specs) folder contains the specification files.

The [`certora/confs`](confs) folder contains a configuration file for each corresponding specification file.

The [`certora/helpers`](helpers) folder contains files that enable the verification of Morpho Blue.

# Getting started

## Certora specification verification

Install `certora-cli` package with `pip install certora-cli`.
To verify specification files, pass to `certoraRun` the corresponding configuration file in the [`certora/confs`](confs) folder.
It requires having set the `CERTORAKEY` environment variable to a valid Certora key.
You can also pass additional arguments, notably to verify a specific rule.
For example, at the root of the repository:

```
certoraRun certora/confs/MerkleTrees.conf --rule wellFormed
```

## Merkle tree verification

To verify that a given list of proofs corresponds to a valid Merkle tree, you must generate a certificate from it.
This assumes that the list of proofs is in the expected JSON format.
For example, at the root of the repository, given a `proofs.json` file:

```
python certora/checker/create_certificate.py proofs.json
```

This requires installing the corresponding libraries first:

```
pip install web3 eth-tester py-evm
```

Then, verify this certificate:

```
FOUNDRY_PROFILE=checker forge test
```
