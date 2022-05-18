# Morpho Protocol V1 🦋

[![Test](https://github.com/morpho-labs/morpho-contracts/actions/workflows/ci-foundry.yml/badge.svg)](https://github.com/morpho-labs/morpho-contracts/actions/workflows/ci-foundry.yml)

This repository contains the core smart contracts for the Morpho Protocol V1 🦋.

---

## Testing with Foundry 🔨

Tests are run against a forks of real networks, which allows us to interact directly with liquidity pools of Compound or Aave. Note that you need to have an RPC provider that have access to Ethereum or Polygon.

For testing, first, install dependencies with:

```
yarn
```

Then, install [Foundry](https://github.com/gakonst/foundry):

Run the command below to get foundryup, the Foundry toolchain installer:

```
curl -L https://foundry.paradigm.xyz | bash
```

If you do not want to use the redirect, feel free to manually download the foundryup installation script from [here](https://github.com/gakonst/foundry).

Then in a new terminal session or after reloading your PATH, run it to get the latest forge and cast binaries:

```
foundryup
```

Finally, update git submodules:

```
git submodule init
git submodule update
```

Refer to the `env.example` for the required environment variable.

In order to have the traces of the run exported as an HTML page, install the aha module.

For OSX users:

```
brew install aha
```

For debian users:

```
apt install aha
```

To run tests on different platforms, navigate a Unix terminal to the root folder of the project and run the command of your choice:

To run every test:

```
make test-compound
```

or to run only the desired section:

```
make c-TestBorrow
make c-TestGovernance
...
```

or to run individual tests:

```
make s-test_higher_than_max_fees
make s-test_claim_fees
...
```

For the other commands, check the `Makefile` file.

---

## Style guide 💅

### Code Formatting

We use prettier with the default configuration mentionned in the [Solidity Prettier Plugin](https://github.com/prettier-solidity/prettier-plugin-solidity).
We recommend developers using VS Code to set their local config as below:

```
{
    "editor.formatOnSave": true,
    "solidity.formatter": "prettier",
    "editor.defaultFormatter": "esbenp.prettier-vscode"
}
```

In doing so the code will be formatted on each save.

We use Husky hook to format code before being pushed to any remote branch to enforce coding style among all developers.

### Code Style

We follow the Solidity style guide from the [Solidity Documentation](https://docs.soliditylang.org/en/latest/style-guide.html) and the [NatSpec format](https://docs.soliditylang.org/en/latest/natspec-format.html) using this pattern `///`.
Comments should begin with a capital letter and end with a period. You can check the current code to have an overview of what is expected.

---

## Contributing 💪

In this section, you will find some guidelines to read before contributing to the project.

### Creating issues and PRs

Guidelines for creating issues and PRs:

- Issues must be created and labelled with relevant labels (type of issues, high/medium/low priority, etc.).
- Nothing should be pushed directly to the `main` branch.
- Pull requests must be created before and branch names must follow this pattern: `feat/<feature-name>`, `test/<test-name>` or `fix/<fix-name>`. `docs`, `ci` can also be used. The goal is to have clear branches names and make easier their management.
- PRs must be labelled with the relevant labels.
- Issues must be linked to PRs so that once the PR is merged related issues are closed at the same time.
- Reviewers must be added to the PR.
- For commits, install the gitmoji VS Code extension and use the appropriate emoji for each commit. It should match this pattern: `<emoji> (<branch-name>) <commit-message>`. For a real world example: `✨ (feat/new-feature) Add new feature`.

### Before merging a PR

Before merging a PR:

- PR must have been reviewed by reviewers. The must deliver a complete report on the smart contracts (see the section below).
- Comments and requested changes must have been resolved.
- PR must have been approved by every reviewers.
- CI must pass.

For smart contract reviews, a complete report must have been done, not just a reading of the changes in the code. This is very important as a simple change on one line of code can bring dramatic consequences on a smart contracts (bad copy/paste have already lead to hacks).
For the guidelines on "How to review contracts and write a report?", you can follow this [link](https://morpho-labs.notion.site/How-to-do-a-Smart-Contract-Review-81d1dc692259463993cc7d81544767d1).

By default, PR are rebased with `dev` before merging to keep a clean historic of commits and the branch is deleted. The same process is done from `dev` to `main`.

## Deploying a contract on a network 🚀

You can run the following command to deploy Morpho's contracts for Aave on Polygon:

```
yarn deploy:aave:polygon
```

For the other commands, check the `package.json` file.

## Publishing and verifying a contract on Etherscan 📡

An etherscan API key is required to verify the contract and placed into your `.env.local` file.
The right arguments of the constructor of the smart contract to verify must be write inside `arguments.js`. Then you can run the following command to verify a contract:

```
npx hardhat verify --network <network-name> --constructor-args scripts/arguments.js <contract-address>
npx hardhat verify --network <network-name> --constructor-args scripts/arguments.js --contract contracts/Example.sol:ExampleContract <contract-address>
```

The second is necessary if contracts with different names share the same ABI.

## Verification on Tenderly 📡

In your `env.local` file, put your tenderly private key. Then you can deploy and directly verify contracts on your tenderly dashboard.

## External resources & documentation 📚

- [General documentation](https://morpho-labs.gitbook.io/morpho-documentation/)
- [Developer documentation](https://morpho-labs.gitbook.io/technical-documentation/)
- [Whitepaper](https://whitepaper.morpho.best)
- [Foundry](https://github.com/gakonst/foundry)
- [Solidity Prettier Plugin](https://github.com/prettier-solidity/prettier-plugin-solidity)

## Questions & Feedback 💬

For any question you can send an email to [merlin@mopho.best](mailto:merlin@morpho.best) 😊
