# Morpho Core Protocol V1

[![Test](https://github.com/morpho-labs/morpho-contracts/actions/workflows/ci-foundry.yml/badge.svg)](https://github.com/morpho-labs/morpho-contracts/actions/workflows/ci-foundry.yml)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://i.imgur.com/uLq5V14.png">
  <img alt="" src="https://i.imgur.com/ZiL1Lr2.png">
</picture>

---

## What is Morpho?

Morpho is a lending pool optimizer: it improves the capital efficiency of positions on existing lending pools by seamlessly matching users peer-to-peer.

- Morpho's rates stay between the supply rate and the borrow rate of the pool, reducing the interests paid by the borrowers while increasing the interests earned by the suppliers. It means that you are getting boosted peer-to-peer rates or, in the worst case scenario, the APY of the pool.
- Morpho also preserves the same experience, the same liquidity and the same parameters (collateral factors, oracles, …) as the underlying pool.

TL;DR: Instead of borrowing or lending on your favorite pool like Compound or Aave, you would be better off using Morpho-Compound or Morpho-Aave.

---

## Contracts overview

In this repository.

The Morpho protocol is designed at its core with a set of contracts acting as a proxy and communicating with upgradeable pieces of logic via calls (to implementation contracts) and delegate calls (to delegation contracts). Here is a brief overview of the Morpho protocol's contracts interactions:

![image](https://user-images.githubusercontent.com/44097430/170581601-307fbaae-2a27-4065-a9d1-f43172e4a30e.png)

The protocol's storage, located at Morpho's main proxy contract, is defined in the `MorphoStorage` (For example for Morpho-Compound: [`MorphoStorage`](./contracts/compound/MorphoStorage.sol)) contract and is used by every delegation contract. Having this overview in mind, Morpho contracts typically fall under the following 4 main categories:

- Core features (supply, borrow, withdraw, repay, liquidate)
- Underlying logic (peer-to-peer matching, positions management)
- Peripheral contracts (lending/borrowing incentives, underlying protocol rewards management)
- Miscellaneous (maths, solidity calls, types)

---

## Documentation

- [White Paper](https://whitepaper.morpho.xyz)
- [Morpho Documentation](https://docs.morpho.xyz)
- Yellow Paper (coming soon)

---

## Bug bounty

A bug bounty is open on Immunefi. The rewards and scope are defined [here](https://immunefi.com/bounty/morpho/).
You can also send an email to [security@morpho.xyz](mailto:security@morpho.xyz) if you find something worrying.

---

## Deployment Addresses

### Morpho-Compound Ethereum

- Morpho Proxy: [0x8888882f8f843896699869179fb6e4f7e3b58888](https://etherscan.io/address/0x8888882f8f843896699869179fb6e4f7e3b58888)
- Morpho Implementation: [0xf29cc0319679b54bd25a8666fc0830b023c6a272](https://etherscan.io/address/0xf29cc0319679b54bd25a8666fc0830b023c6a272)
- PositionsManager: [0x082bf6702e718483c85423bd279088c215a21302](https://etherscan.io/address/0x082bf6702e718483c85423bd279088c215a21302)
- InterestRatesManager: [0x2f2d51f4d68a96859d4f69672cbeefd854bd8289](https://etherscan.io/address/0x2f2d51f4d68a96859d4f69672cbeefd854bd8289)
- RewardsManager Proxy: [0x78681e63b6f3ad81ecd64aecc404d765b529c80d](https://etherscan.io/address/0x78681e63b6f3ad81ecd64aecc404d765b529c80d)
- RewardsManager Implementation: [0x70c59877f5358d8d6f2fc90f53813eb2b2698ab7](https://etherscan.io/address/0x70c59877f5358d8d6f2fc90f53813eb2b2698ab7)
- Lens: [0xe8cfa2edbdc110689120724c4828232e473be1b2](https://etherscan.io/address/0xe8cfa2edbdc110689120724c4828232e473be1b2)
- CompRewardsLens: [0x9e977f745d5ae26c6d47ac5417ee112312873ba7](https://etherscan.io/address/0x9e977f745d5ae26c6d47ac5417ee112312873ba7)

### Morpho-Aave-V2 Ethereum

- Morpho Proxy: [0x299ff2534c6f11624d6a65463b8b40c958ab668f](https://etherscan.io/address/0x299ff2534c6f11624d6a65463b8b40c958ab668f)
- Morpho Implementation: [0x299ff2534c6f11624d6a65463b8b40c958ab668f](https://etherscan.io/address/0x299ff2534c6f11624d6a65463b8b40c958ab668f)
- EntryPositionsManager: [0xdf93cf1ca3acf96bc26783e6fab89400d362d0b4](https://etherscan.io/address/0xdf93cf1ca3acf96bc26783e6fab89400d362d0b4)
- ExitPositionsManager: [0xf6998f72b92b81c8f683d30ed8678d348fe9754b](https://etherscan.io/address/0xf6998f72b92b81c8f683d30ed8678d348fe9754b)
- InterestRatesManager: [0x91b23044d4a8089670309852c7f0a93e5ca8efb7](https://etherscan.io/address/0x91b23044d4a8089670309852c7f0a93e5ca8efb7)
- Lens Proxy: [0x507fa343d0a90786d86c7cd885f5c49263a91ff4](https://etherscan.io/address/0x507fa343d0a90786d86c7cd885f5c49263a91ff4)
- Lens: [0x8706256509684e9cd93b7f19254775ce9324c226](https://etherscan.io/address/0x8706256509684e9cd93b7f19254775ce9324c226)

### Common Ethereum

- ProxyAdmin: [0x99917ca0426fbc677e84f873fb0b726bb4799cd8](https://etherscan.io/address/0x99917ca0426fbc677e84f873fb0b726bb4799cd8)

---

## Testing with [Foundry](https://github.com/foundry-rs/foundry) 🔨

Tests are run against a forks of real networks, which allows us to interact directly with liquidity pools of Compound or Aave. Note that you need to have an RPC provider that have access to Ethereum or Polygon.

For testing, make sure `yarn` and `foundry` are installed and install dependencies (node_modules, git submodules) with:

```bash
make install
```

Alternatively, if you only want to set up

Refer to the `env.example` for the required environment variable.

To run tests on different protocols, navigate a Unix terminal to the root folder of the project and run the command of your choice:

To run every test of a specific protocol (e.g. for Morpho-Compound):

```bash
make test PROTOCOL=compound
```

or to run only a specific set of tests of a specific protocol (e.g. for Morpho-Aave V2):

```bash
make c-TestBorrow PROTOCOL=aave-v2
```

or to run an individual test of a specific protocol (e.g. for Morpho-Aave V3):

```bash
make s-testShouldCollectTheRightAmountOfFees PROTOCOL=aave-v3
```

For the other commands, check the [Makefile](./Makefile).

---

## Testing with Hardhat

Only tests for the [RewardsDistributor](./contracts/common/rewards-distribution/RewardsDistributor.sol) are run with Hardhat.

Just run:

```bash
yarn test
```

---

## Deployment & Upgrades

### Network mode (default)

Run the Foundry deployment script with:

```bash
make script-Deploy PROTOCOL=compound NETWORK=goerli
```

### Local mode

First start a local EVM:

```bash
make anvil NETWORK=goerli
```

Then run the Foundry deployment script in a separate shell, using `SMODE=local`:

```bash
make script-Deploy PROTOCOL=compound NETWORK=goerli SMODE=local
```

---

## Questions & Feedback

For any question or feedback you can send an email to [merlin@morpho.xyz](mailto:merlin@morpho.xyz).

---

## Licensing

The code is under the GNU General Public License v3.0 license, see [`LICENSE`](https://github.com/morphodao/morpho-core-v1/blob/main/LICENSE).
