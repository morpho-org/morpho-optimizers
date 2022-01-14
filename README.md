# Morpho Protocol V0 🦋

[![Tests](https://github.com/morpho-protocol/morpho-contracts/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/morpho-protocol/morpho-contracts/actions/workflows/tests.yml)
[![codecov](https://codecov.io/gh/morpho-protocol/morpho-contracts/branch/main/graph/badge.svg?token=ZSX5RRQG36)](https://codecov.io/gh/morpho-protocol/morpho-contracts)

This repository contains the core smart contracts for the Morpho Protocol V0 🦋.

# Testing

## Testing in Solidity with Foundry

First, install [Foundry](https://github.com/gakonst/foundry):

```
cargo install --git https://github.com/gakonst/foundry --bin forge --locked
```

Also, you should update git submodules to install the ds-test library:
```
git submodule init
git submodule update
```

Refer to the `env.example` for the required environment variable.

Tests are run against a forks of real networks, which allows us to interact directly with liquidity pools of Compound or Aave. Note that you need to have an RPC provider that have access to Ethereum or Polygon.
We aim a test coverage > 90% of all functions.

⚠️ Tests cannot substituted to coverage as the coverage command as contracts are compiled without optimization and can alter some patterns.

To run tests on different platforms, navigate a Unix terminal to the root folder of the project and run the command of your choice:

To run every test:

```
make test
```

or to run only the desired section:

```
make TestBorrow
make TestGovernance
...
```

For the other commands, check the `Makefile` file.

## Testing in Javascript with Hardhat

First, install dependencies with:

```
yarn
```

Refer to the `env.example` for the required environment variable.

Tests are run against a forks of real networks, which allows us to interact directly with liquidity pools of Compound or Aave. Note that you need to have an RPC provider that have access to Ethereum or Polygon.
We aim a test coverage > 90% of all functions.

⚠️ Tests cannot substituted to coverage as the coverage command as contracts are compiled without optimization and can alter some patterns.

To run tests on different platforms, use these commands:

```
yarn test:comp:mainnet
```

or

```
yarn test:aave:polygon
```

For coverage, run:

```
yarn coverage
```

For the other commands, check the `package.json` file.

## Code Formatting

We use prettier with the default configuration mentionned in the [Solidity Prettier Plugin](https://github.com/prettier-solidity/prettier-plugin-solidity).
We recommend developers using VSCODE to set their local config as below:

```

{
    "editor.formatOnSave": true,
    "solidity.formatter": "prettier",
    "editor.defaultFormatter": "esbenp.prettier-vscode"
}

```

In doing so the code will be formatted on each save.

We use Husky hook to format code before being pushed to any remote branch to enforce coding style among all developers.

## Contributing

In this section, you will find some guidelines to read before contributing to the project.

### Creating issues and PRs

Guidelines for creating issues and PRs:

- Issues must be created and labelled with relevant labels (type of issues, high/medium/low priority, etc.).
- Nothing should be pushed directly to the `main` branch.
- Pull requests must be created before and branch names must follow this pattern: `feat/<feature-name>`, `test/<test-name>` or `fix/<fix-name>`. `docs`, `ci` can also be used. The goal is to have clear branches names and make easier their management.
- PRs must be labelled with the relevant labels.
- Issues must be linked to PRs so that once the PR is merged related issues are closed at the same time.
- Reviewers must be added to the PR.
- For commits, we use the [conventional commits pattern](https://www.conventionalcommits.org/en/v1.0.0/).

### Before merging a PR

Before merging a PR:

- PR must have been reviewed by reviewers. The must deliver a complete report on the smart contracts (see the section below).
- Comments and requested changes must have been resolved.
- PR must have been approved by every reviewers.
- CI must pass.

For smart contract reviews, a complete report must have been done, not just a reading of the changes in the code. This is very important as a simple change on one line of code can bring dramatic consequences on a smart contracts (bad copy/paste have already lead to hacks).
For the guidelines on "How to review contracts and write a report?", you can follow this [link](https://abiding-machine-635.notion.site/Solidity-Guidelines-7c9a201413df47d6b72577374f93a697).

By default, PR are rebased with `main` before merging to keep a clean historic of commits and the branch is deleted.

## Deploying a contract on a network

You can run the following command to deploy Morpho's contracts on top of Aave on Polygon:

```

yarn deploy:aave:polygon

```

For the other commands, check the `package.json` file.

## Publishing and verifying a contract on Etherscan

An etherscan API key is required to verify the contract and placed into your `.env` local file.
The right arguments of the constructor of the smart contract to verify must be write inside `arguments.js`. Then you can run the following command to verify a contract:

```

npx hardhat verify --network <network-name> --constructor-args scripts/arguments.js <contract-address>
npx hardhat verify --network <network-name> --constructor-args scripts/arguments.js --contract contracts/Example.sol:ExampleContract <contract-address>

```

The second is necessary if contracts with different names share the same ABI.

## Verification on Tenderly

In your `env.local` file, put your tenderly private key. Then you can deploy and directly verify contracts on your tenderly dashboard.

## External resources & documentation

- [Solidity Prettier Plugin](https://github.com/prettier-solidity/prettier-plugin-solidity)
- [Codecov](https://github.com/codecov/example-node)
- [PRBMath](https://github.com/hifi-finance/prb-math): we use this library to handle fixed-point math.
- [Red Black Binary Tree](https://en.wikipedia.org/wiki/Red%E2%80%93black_tree): binary tree used to sort users for the matching engine
- [Red Black Binary Tree Solidity Implementation 1](https://github.com/bokkypoobah/BokkyPooBahsRedBlackTreeLibrary): base solidity implementation of a Red Black Binary Tree.
- [Red Black Binary Tree Solidity Implementation 2](https://github.com/rob-Hitchens/OrderStatisticsTree): solidity implementation of a Red Black Binary Tree based on the previous version. Our modified version makes keys unique items instead of just (key, value) unique pairs.

## Questions

For any question you can send an email to [merlin@mopho.best](mailto:merlin@morpho.best) 😊
```
