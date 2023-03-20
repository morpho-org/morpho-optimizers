# Running the certora verification tool

These instructions detail the process for running the Certora Prover.

Documentation for CVT and the specification language are available
[here](https://docs.certora.com/)


## Directory contents and organization

`scripts`
: Scripts in this directory are used to run different parts of the verification.

`spec`
: Files in this directory contain specifications to be verified

`helpers`
: These files contain dummy implementations of common interfaces.  They are
  useful for `DISPATCHER` method summaries (see [method summarization](summaries))

`harness`
: These contracts extend the contracts to be verified to add functionality
  needed for the prover.  See ([harnessing](harnessing)) for more information.

`applyHarness.patch`, `Makefile` and `munged` directory
: These files are used to make systematic changes to the contracts to be
  verified.  See ([harnessing](harnessing)) for more information.

[summaries]:  https://docs.certora.com/en/latest/docs/ref-manual/cvl/methods.html
[harnessing]: https://docs.certora.com/en/latest/docs/ref-manual/approx/harnessing.html

## Running the verification

The scripts in the `certora/scripts` directory are used to submit verification
jobs to the Certora verification service. These scripts should be run from the
root directory; for example by running

```sh
sh certora/scripts/verifyExampleContract.sh <arguments>
```

After the job is complete, the results will be available on
[the staging Certora portal](https://prover.certora.com/). 

## Adapting to changes

Some of our rules require the code to be simplified in various ways. Our
primary tool for performing these simplifications is to run verification on a
contract that extends the original contracts and overrides some of the methods.
These "harness" contracts can be found in the `certora/harness` directory.

This pattern does require some modifications to the original code: some methods
need to be made virtual or public, for example. These changes are handled by
applying a patch to the code before verification.

When one of the `verify` scripts is executed, it first applies the patch file
`certora/applyHarness.patch` to the `contracts` directory, placing the output
in the `certora/munged` directory. We then verify the contracts in the
`certora/munged` directory.

If the original contracts change, it is possible to create a conflict with the
patch. In this case, the verify scripts will report an error message and output
rejected changes in the `munged` directory. After merging the changes, run
`make record` in the `certora` directory; this will regenerate the patch file,
which can then be checked into git.

Note: there have been reports of unexpected behavior on mac, see
[issue CUST-62](https://certora.atlassian.net/browse/CUST-62?atlOrigin=eyJpIjoiZWI1MGFjNGZkZGE0NGFlNjkwYjUwYjY2NmE4ZmQ1OTIiLCJwIjoiaiJ9).

