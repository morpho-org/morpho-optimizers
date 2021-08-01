# Morpho Protocol V0 🦋

[![Tests](https://github.com/morpho-protocol/morpho-contracts/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/morpho-protocol/morpho-contracts/actions/workflows/tests.yml)
[![codecov](https://codecov.io/gh/morpho-protocol/morpho-contracts/branch/main/graph/badge.svg?token=ZSX5RRQG36)](https://codecov.io/gh/morpho-protocol/morpho-contracts)

This repository contains the core smart contracts for the Morpho Protocol V0 🦋.

## Testing

Test are run against a fork fo the mainnet, which allows us to interact with directly with Compound.
We aim a test coverage > 90% of all functions.

⚠️ Tests cannot substituted to coverage as the coverage command as contracts are compiled without optimization and can alter some patterns.

To run test, you can run:
```
yarn test
```

For coverage, run:
```
yarn coverage
```

## Code Fromatting

We use prettier with the default configuration mentionned in the [Solidity Prettier Plugin](https://github.com/prettier-solidity/prettier-plugin-solidity).
We recommend developers using VSCODE to set their local config as below:
```
{
	"editor.formatOnSave": true,
	"solidity.formatter": "prettier",
	"[solidity]": {
		"editor.defaultFormatter": "JuanBlanco.solidity"
	}
}
```
In doing so the code will be formatted on each save.

We use Husky hook to format code before being pushed to any remote branch to enforce coding style among all developers.

### External resources & documentation

 - [Chainlink Oracle](https://docs.chain.link/docs/get-the-latest-price/)
 - [Solidity Prettier Plugin](https://github.com/prettier-solidity/prettier-plugin-solidity)
 - [Codecov](https://github.com/codecov/example-node)