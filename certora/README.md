This folder contains the verification of the Morpho Optimizers using CVL, Certora's Verification Language.

# Folder and file structure

The [`certora/specs`](specs) folder contains the specification files.

The [`certora/confs`](confs) folder contains a configuration file for each corresponding specification file.

The [`certora/harness`](harness) folder contains contracts that enable the verification of Morpho Blue.
Notably, this allows handling the fact that library functions should be called from a contract to be verified independently, and it allows defining needed getters.

# Getting started

Install `certora-cli` package with `pip install certora-cli`.
To verify specification files, pass to `certoraRun` the corresponding configuration file in the [`certora/confs`](confs) folder.
It requires having set the `CERTORAKEY` environment variable to a valid Certora key.
You can also pass additional arguments, notably to verify a specific rule.
For example, at the root of the repository:

```
certoraRun certora/confs/MerkleTrees.conf --rule wellFormed
```
