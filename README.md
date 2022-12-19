# Morpho Core Protocol V1

[![Morpho-Compound](https://github.com/morpho-dao/morpho-v1/actions/workflows/ci-foundry-compound.yml/badge.svg)](https://github.com/morpho-dao/morpho-v1/actions/workflows/ci-foundry-compound.yml)
[![Morpho-AaveV2](https://github.com/morpho-dao/morpho-v1/actions/workflows/ci-foundry-aave-v2.yml/badge.svg)](https://github.com/morpho-dao/morpho-v1/actions/workflows/ci-foundry-aave-v2.yml)

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

The Morpho protocol is designed at its core with a set of contracts delegating calls to implementation contracts (to overcome the contract size limit).

Here is a brief overview of the Morpho protocol's contracts interactions:

![image](https://user-images.githubusercontent.com/3147812/187162991-d9e94841-0f23-4f25-86d4-a495917b70e7.png)

The main user's entry points are exposed in the `Morpho` contract. It inherits from `MorphoGovernance` which contains all the admin functions of the DAO, `MorphoUtils`, and `MorphoStorage`, where the protocol's storage is located. This contract delegates call to other contracts, that have the exact same storage layout:

- `PositionsManager`: logic of basic supply, borrow, withdraw, repay and liquidate functions. In Morpho-Aave, it is separated into two contracts, `EntryPositionsManager` and `ExitPositionsManager`. These contracts inherit from `MatchingEngine`, which contains the matching engine internal functions.
- `InterestRatesManager`: logic of indexes computation.

It also interacts with `RewardsManager`, which manages the underlying pool's rewards if any.

---

## Documentation

- [White Paper](https://whitepaper.morpho.xyz)
- [Morpho Documentation](https://docs.morpho.xyz)
- Yellow Paper (coming soon)

---

## Audits

All audits are stored in the [audits](./audits/)' folder.

---

## Bug bounty

A bug bounty is open on Immunefi. The rewards and scope are defined [here](https://immunefi.com/bounty/morpho/).
You can also send an email to [security@morpho.xyz](mailto:security@morpho.xyz) if you find something worrying.

---

## Deployment Addresses

### Morpho-Compound Ethereum

- Morpho Proxy: [0x8888882f8f843896699869179fb6e4f7e3b58888](https://etherscan.io/address/0x8888882f8f843896699869179fb6e4f7e3b58888)
- Morpho Implementation: [0xbbb011b923f382543a94e67e1d0c88d9763356e5](https://etherscan.io/address/0xbbb011b923f382543a94e67e1d0c88d9763356e5)
- PositionsManager: [0x309a4505d79fcc59affaba205fdcb880d400ef39](https://etherscan.io/address/0x309a4505d79fcc59affaba205fdcb880d400ef39)
- InterestRatesManager: [0x3e483225666871d192b686c42e6834e217a9871c](https://etherscan.io/address/0x3e483225666871d192b686c42e6834e217a9871c)
- RewardsManager Proxy: [0x78681e63b6f3ad81ecd64aecc404d765b529c80d](https://etherscan.io/address/0x78681e63b6f3ad81ecd64aecc404d765b529c80d)
- RewardsManager Implementation: [0xf47963cc317ebe4b8ebcf30f6e144b7e7e5571b7](https://etherscan.io/address/0xf47963cc317ebe4b8ebcf30f6e144b7e7e5571b7)
- Lens Proxy: [0x930f1b46e1d081ec1524efd95752be3ece51ef67](https://etherscan.io/address/0x930f1b46e1d081ec1524efd95752be3ece51ef67)
- Lens Implementation: [0xe54dde06d245fadcba50dd786f717d44c341f81b](https://etherscan.io/address/0xe54dde06d245fadcba50dd786f717d44c341f81b)
- CompRewardsLens: [0x9e977f745d5ae26c6d47ac5417ee112312873ba7](https://etherscan.io/address/0x9e977f745d5ae26c6d47ac5417ee112312873ba7)

### Morpho-Aave-V2 Ethereum

- Morpho Proxy: [0x777777c9898d384f785ee44acfe945efdff5f3e0](https://etherscan.io/address/0x777777c9898d384f785ee44acfe945efdff5f3e0)
- Morpho Implementation: [0x206a1609a484db5129ca118f138e5a8abb9c61e0](https://etherscan.io/address/0x206a1609a484db5129ca118f138e5a8abb9c61e0)
- EntryPositionsManager: [0x2a46cad23484c15f60663ece368395b3a249632a](https://etherscan.io/address/0x2a46cad23484c15f60663ece368395b3a249632a)
- ExitPositionsManager: [0xfa652aa169c23277a941cf2d23d2d707fda60ed9](https://etherscan.io/address/0xfa652aa169c23277a941cf2d23d2d707fda60ed9)
- InterestRatesManager: [0x4f54235e17eb8dcdfc941a77e7734a537f7bed86](https://etherscan.io/address/0x4f54235e17eb8dcdfc941a77e7734a537f7bed86)
- Lens Proxy: [0x507fa343d0a90786d86c7cd885f5c49263a91ff4](https://etherscan.io/address/0x507fa343d0a90786d86c7cd885f5c49263a91ff4)
- Lens Implementation: [0xce23e457fb01454b8c59e31f4f72e4bd3d29b5eb](https://etherscan.io/address/0xce23e457fb01454b8c59e31f4f72e4bd3d29b5eb)

### Common Ethereum

- ProxyAdmin: [0x99917ca0426fbc677e84f873fb0b726bb4799cd8](https://etherscan.io/address/0x99917ca0426fbc677e84f873fb0b726bb4799cd8)

---

## Importing package

Using npm:

```bash
npm install @morpho-dao/morpho-v1
```

Using forge:

```bash
forge install @morpho-dao/morpho-v1@v2.0.0
```

Using git submodules:

```bash
git submodules add @morpho-dao/morpho-v1@v2.0.0
```

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

or to run an individual test of a specific protocol (e.g. for Morpho-Aave V2):

```bash
make test-testBorrow1 PROTOCOL=aave-v2
```

For the other commands, check the [Makefile](./Makefile).

---

## Testing with Hardhat

Only tests for the [RewardsDistributor](./src/common/rewards-distribution/RewardsDistributor.sol) are run with Hardhat.

Just run:

```bash
yarn test
```

---

## Test coverage

Test coverage is reported using [foundry](https://github.com/foundry-rs/foundry) coverage with [lcov](https://github.com/linux-test-project/lcov) report formatting (and optionally, [genhtml](https://manpages.ubuntu.com/manpages/xenial/man1/genhtml.1.html) transformer).

To generate the `lcov` report, run:

```bash
make coverage
```

The report is then usable either:

- via [Coverage Gutters](https://marketplace.visualstudio.com/items?itemName=ryanluker.vscode-coverage-gutters) following [this tutorial](https://mirror.xyz/devanon.eth/RrDvKPnlD-pmpuW7hQeR5wWdVjklrpOgPCOA-PJkWFU)
- via html, using `make lcov-html` to transform the report and opening `coverage/index.html`

:warning: Test coverage is not available on Morpho-AaveV2 for [this reason](https://github.com/foundry-rs/foundry/issues/3357#issuecomment-1297192171)

---

## Storage seatbelt

2 CI pipelines are currently running on every PR to check that the changes introduced are not modifying the storage layout of proxied smart contracts in an unsafe way:

- [storage-layout.sh](./scripts/storage-layout.sh) checks that the latest foundry storage layout snapshot is identical to the committed storage layout snapshot
- [foundry-storage-check](https://github.com/Rubilmax/foundry-storage-diff) is in test phase and will progressively replace the snapshot check

In the case the storage layout snapshots checked by `storage-layout.sh` are not identical, the developer must commit the updated storage layout snapshot stored under [snapshots/](./snapshots/) by running:

- `make storage-layout-generate` with the appropriate protocol parameters

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

The code is under the GNU AFFERO GENERAL PUBLIC LICENSE v3.0, see [`LICENSE`](./LICENSE).
