import * as dotenv from 'dotenv';
dotenv.config({ path: './.env.local' });
import { utils, BigNumber, Signer, Contract } from 'ethers';
import hre, { ethers } from 'hardhat';
import { expect } from 'chai';
const config = require(`@config/${process.env.NETWORK}-config.json`);
import { MAX_INT, removeDigitsBigNumber, bigNumberMin, to6Decimals, getTokens } from './utils/common-helpers';
import {
  WAD,
  // RAY,
  // underlyingToScaledBalance,
  // scaledBalanceToUnderlying,
  // underlyingToP2PUnit,
  // p2pUnitToUnderlying,
  // underlyingToAdUnit,
  // aDUnitToUnderlying,
  // computeNewMorphoExchangeRate,
} from './utils/aave-helpers';

// Commands to use those tests :
// terminal 1 : NETWORK=polygon-mainnet npx hardhat node
// terminal 2 : npx hardhat test test/aave-fuzzing.ts
// if the fuzzing finds a bug, the test script will stop
// and you can investigate the problem using the blockchain still
// running in terminal 2

describe('PositionsManagerForAave Contract', function () {
  this.timeout(100_000_000);

  const LIQUIDATION_CLOSE_FACTOR_PERCENT: BigNumber = BigNumber.from(5000);
  const SECOND_PER_YEAR: BigNumber = BigNumber.from(31536000);
  const PERCENT_BASE: BigNumber = BigNumber.from(10000);
  const AVERAGE_BLOCK_TIME: number = 2;

  // Tokens
  let aDaiToken: Contract;
  let aUsdcToken: Contract;
  let daiToken: Contract;
  let usdcToken: Contract;
  // let wbtcToken: Contract;
  // let wmaticToken: Contract;
  let variableDebtDaiToken: Contract;

  // Contracts
  let positionsManagerForAave: Contract;
  let marketsManagerForAave: Contract;
  let fakeAavePositionsManager: Contract;
  let lendingPool: Contract;
  let lendingPoolAddressesProvider: Contract;
  let protocolDataProvider: Contract;
  let oracle: Contract;
  // let priceOracle: Contract;

  let underlyingThreshold: BigNumber;
  let nonce: BigNumber;

  type Market = {
    token: Contract;
    config: any;
    aToken: Contract;
    loanToValue: number; // in percent
    liqThreshold: number; // in percent
    name: string;
    slotPosition: number;
    index: number;
    ethPerUnit: BigNumber; // value factor in Eth's weis per Unit
  };

  let markets: Array<Market>;

  const initialize = async () => {
    ethers.provider = new ethers.providers.JsonRpcProvider('http://127.0.0.1:8545/');
    const owner = await ethers.getSigner('0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266');

    // Deploy DoubleLinkedList
    const DoubleLinkedList = await ethers.getContractFactory('contracts/aave/libraries/DoubleLinkedList.sol:DoubleLinkedList');
    const doubleLinkedList = await DoubleLinkedList.deploy();
    await doubleLinkedList.deployed();

    // Deploy MarketsManagerForAave
    const MarketsManagerForAave = await ethers.getContractFactory('MarketsManagerForAave');
    marketsManagerForAave = await MarketsManagerForAave.deploy(config.aave.lendingPoolAddressesProvider.address);
    await marketsManagerForAave.deployed();

    // Deploy PositionsManagerForAave
    const PositionsManagerForAave = await ethers.getContractFactory('PositionsManagerForAave');
    positionsManagerForAave = await PositionsManagerForAave.deploy(
      marketsManagerForAave.address,
      config.aave.lendingPoolAddressesProvider.address
    );
    fakeAavePositionsManager = await PositionsManagerForAave.deploy(
      marketsManagerForAave.address,
      config.aave.lendingPoolAddressesProvider.address
    );
    await positionsManagerForAave.deployed();
    await fakeAavePositionsManager.deployed();

    // Get contract dependencies
    const aTokenAbi = require(config.tokens.aToken.abi);
    const variableDebtTokenAbi = require(config.tokens.variableDebtToken.abi);
    aDaiToken = await ethers.getContractAt(aTokenAbi, config.tokens.aDai.address, owner);
    aUsdcToken = await ethers.getContractAt(aTokenAbi, config.tokens.aUsdc.address, owner);
    variableDebtDaiToken = await ethers.getContractAt(variableDebtTokenAbi, config.tokens.variableDebtDai.address, owner);
    lendingPool = await ethers.getContractAt(require(config.aave.lendingPool.abi), config.aave.lendingPool.address, owner);
    lendingPoolAddressesProvider = await ethers.getContractAt(
      require(config.aave.lendingPoolAddressesProvider.abi),
      config.aave.lendingPoolAddressesProvider.address,
      owner
    );
    protocolDataProvider = await ethers.getContractAt(
      require(config.aave.protocolDataProvider.abi),
      lendingPoolAddressesProvider.getAddress('0x1000000000000000000000000000000000000000000000000000000000000000'),
      owner
    );
    oracle = await ethers.getContractAt(require(config.aave.oracle.abi), lendingPoolAddressesProvider.getPriceOracle(), owner);

    // Mint some tokens
    daiToken = await ethers.getContractAt(require(config.tokens.dai.abi), config.tokens.dai.address, owner);
    usdcToken = await ethers.getContractAt(require(config.tokens.usdc.abi), config.tokens.usdc.address, owner);

    // wbtcToken = await getTokens(config.tokens.wbtc.whale, 'whale', signers, config.tokens.wbtc, BigNumber.from(10).pow(8));
    // wmaticToken = await getTokens(config.tokens.wmatic.whale, 'whale', signers, config.tokens.wmatic, utils.parseUnits('100'));
    underlyingThreshold = WAD;

    // Create and list markets
    await marketsManagerForAave.connect(owner).setPositionsManager(positionsManagerForAave.address);
    await marketsManagerForAave.connect(owner).setLendingPool();
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aDai.address, WAD, MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aUsdc.address, to6Decimals(WAD), MAX_INT);
    // await marketsManagerForAave.connect(owner).createMarket(config.tokens.aWbtc.address, BigNumber.from(10).pow(4), MAX_INT);
    // await marketsManagerForAave.connect(owner).createMarket(config.tokens.aUsdt.address, to6Decimals(WAD), MAX_INT);
    // await marketsManagerForAave.connect(owner).createMarket(config.tokens.aWmatic.address, WAD, MAX_INT);

    let daiMarket: Market = {
      token: daiToken,
      config: config.tokens.dai,
      aToken: aDaiToken,
      loanToValue: 75,
      liqThreshold: 80,
      name: 'dai',
      slotPosition: 0,
      index: 0,
      ethPerUnit: BigNumber.from('0xd2bbd688b200'), // took from aave's oracle at pinned block
    };
    let usdcMarket: Market = {
      token: usdcToken,
      config: config.tokens.usdc,
      aToken: aUsdcToken,
      loanToValue: 80,
      liqThreshold: 85,
      name: 'usdc',
      slotPosition: 0,
      index: 1,
      ethPerUnit: BigNumber.from('0xd37144db7c00'), // took from aave's oracle at pinned block
    };

    markets = [daiMarket, usdcMarket];
  };

  before(initialize);

  const toBytes32 = (bn: BigNumber): string => {
    return ethers.utils.hexlify(ethers.utils.zeroPad(bn.toHexString(), 32));
  };

  const setStorageAt = async (address: string, index: string, value: string): Promise<void> => {
    await ethers.provider.send('hardhat_setStorageAt', [address, index, value]);
    await ethers.provider.send('evm_mine', []); // Just mines to the next block
  };

  const tokenAmountToReadable = (bn: BigNumber, token: Contract): string => {
    if (isA6DecimalsToken(token)) return bn.div(1e6).toString();
    else return bn.div(WAD).toString();
  };

  const ethAmountToReadable = (bn: BigNumber): string => {
    return bn.div(BigNumber.from(10).pow(15)).toString() + ' ETH finneys';
  };

  const giveTokensTo = async (token: string, receiver: string, amount: BigNumber, slotPosition: number): Promise<void> => {
    // Get storage slot index
    let index = ethers.utils.solidityKeccak256(
      ['uint256', 'uint256'],
      [receiver, slotPosition] // key, slot
    );
    await setStorageAt(token, index, toBytes32(amount));
  };

  const isA6DecimalsToken = (token: Contract): boolean => {
    return token.address === config.tokens.usdc.address || token.address === config.tokens.usdt.address;
  };

  const from6To18Decimals = (amount: BigNumber): BigNumber => {
    return amount.mul(BigNumber.from(10).pow(12));
  };

  const min = (a: BigNumber, b: BigNumber): BigNumber => {
    if (a.lte(b)) return a;
    else return b;
  };

  before(initialize);

  type Account = {
    address: string;
    signer: Signer;
    index: number;
    deposits: BigNumber[]; // the index in the array represents the deposited token, amounts in same decimals as token
    loans: BigNumber[]; // the index in the array represents the deposited token, amounts in same decimals as token
  };

  describe('PositionsManager fuzzing', () => {
    let accounts: Array<Account> = [];

    const generateAccount = async (): Promise<Account> => {
      let tokenDropSucceeded: boolean;
      let tempDropSucceeded: boolean;
      let ret: Account;
      do {
        tokenDropSucceeded = true;
        let retSign: Signer = ethers.Wallet.createRandom();
        retSign = retSign.connect(ethers.provider);
        let retAddr: string = await retSign.getAddress();
        await ethers.provider.send('hardhat_setBalance', [retAddr, utils.hexValue(utils.parseUnits('10000'))]);
        ret = {
          address: retAddr,
          signer: retSign,
          index: accounts.length,
          deposits: markets.map((): BigNumber => BigNumber.from(0)),
          loans: markets.map((): BigNumber => BigNumber.from(0)),
        };
        for await (let market of markets) {
          tempDropSucceeded = await tryGiveTokens(ret, market);
          tokenDropSucceeded = tokenDropSucceeded && tempDropSucceeded;
        }
      } while (!tokenDropSucceeded); // as the token drop fails for some addresses, we loop until it works
      accounts.push(ret);
      return ret;
    };

    const logAccountData = (account: Account): void => {
      console.log(`--- start account ${account.index} ---`);
      for (let market of markets) {
        console.log(`${tokenAmountToReadable(account.deposits[market.index], market.token)} ${market.name} supplied`);
        console.log(`${tokenAmountToReadable(account.loans[market.index], market.token)} ${market.name} borrowed`);
      }
      console.log(`--- ~end~ account ${account.index} ---`);
    };

    const getEthValueOfDeposits = (account: Account): BigNumber => {
      let sum: BigNumber = BigNumber.from(0);
      let toAdd: BigNumber;
      let divisor: BigNumber;
      for (let market of markets) {
        divisor = isA6DecimalsToken(market.token) ? BigNumber.from(10).pow(6) : BigNumber.from(10).pow(18);
        toAdd = account.deposits[market.index].mul(market.ethPerUnit).div(divisor);
        sum = sum.add(toAdd);
      }
      return sum; // in Weis
    };

    const getLoansImmobilizedEthValue = (account: Account): BigNumber => {
      let sum: BigNumber = BigNumber.from(0);
      let toAdd: BigNumber;
      let divisor: BigNumber;
      for (let market of markets) {
        divisor = isA6DecimalsToken(market.token) ? BigNumber.from(10).pow(6) : BigNumber.from(10).pow(18);
        toAdd = account.loans[market.index].mul(market.ethPerUnit).div(divisor).mul(100).div(market.loanToValue);
        sum = sum.add(toAdd);
      }
      return sum; // in Weis
    };

    const supply = async (account: Account, market: Market): Promise<void> => {
      // the amount to supply is chosen randomly between 1 and 1000 (1 minimum to avoid below threshold error)
      let amount: BigNumber = utils.parseUnits(Math.round(Math.random() * 1000).toString()).add(WAD);
      if (isA6DecimalsToken(market.token)) {
        amount = to6Decimals(amount);
      }
      await market.token.connect(account.signer).approve(positionsManagerForAave.address, amount);
      console.log(account.index, 'supplied', tokenAmountToReadable(amount, market.token), market.name);
      await positionsManagerForAave.connect(account.signer).supply(market.aToken.address, amount);
      account.deposits[market.index] = account.deposits[market.index].add(amount);
      accounts[account.index] = account;
    };

    const borrow = async (account: Account, market: Market): Promise<void> => {
      let toBorrow: BigNumber;
      let minAmount = WAD;
      let factor: BigNumber = isA6DecimalsToken(market.token) ? BigNumber.from(10).pow(6) : BigNumber.from(10).pow(18);
      if (isA6DecimalsToken(market.token)) {
        minAmount = to6Decimals(minAmount);
      }
      let maxAmount: BigNumber = getEthValueOfDeposits(account)
        .sub(getLoansImmobilizedEthValue(account))
        .div(market.ethPerUnit)
        .mul(factor)
        .mul(market.loanToValue)
        .div(100);
      if (maxAmount.gt(minAmount)) {
        toBorrow = maxAmount
          .sub(minAmount)
          .mul(BigNumber.from(Math.floor(Math.random() * 1000)))
          .div(1000);
        if (!toBorrow.add(minAmount).gt(maxAmount)) toBorrow = toBorrow.add(minAmount);
        console.log(account.index, 'borrowed', tokenAmountToReadable(toBorrow, market.token), market.name);
        await positionsManagerForAave.connect(account.signer).borrow(market.aToken.address, toBorrow);
        account.loans[market.index] = account.loans[market.index].add(toBorrow);
      }
      accounts[account.index] = account;
    };

    const withdraw = async (account: Account, market: Market): Promise<void> => {
      let minima: BigNumber = isA6DecimalsToken(market.token) ? to6Decimals(WAD) : WAD;
      let factor: BigNumber = isA6DecimalsToken(market.token) ? BigNumber.from(10).pow(6) : BigNumber.from(10).pow(18);
      if (!account.deposits[market.index].isZero()) {
        let withdrawableAmount: BigNumber = min(
          getEthValueOfDeposits(account).sub(getLoansImmobilizedEthValue(account)).div(market.ethPerUnit).mul(factor),
          account.deposits[market.index]
        );
        let toWithdraw = BigNumber.from(Math.floor(Math.random() * 1000))
          .mul(withdrawableAmount)
          .div(1000);
        if (toWithdraw.lt(minima)) toWithdraw = toWithdraw.add(minima);
        if (toWithdraw.lt(withdrawableAmount)) {
          console.log(account.index, 'withdrew', tokenAmountToReadable(toWithdraw, market.token), market.name);
          await positionsManagerForAave.connect(account.signer).withdraw(market.aToken.address, toWithdraw);
          account.deposits[market.index] = account.deposits[market.index].sub(toWithdraw);
        }
      }
      accounts[account.index] = account;
    };

    const repay = async (account: Account, market: Market): Promise<void> => {
      let minima: BigNumber = isA6DecimalsToken(market.token) ? to6Decimals(WAD) : WAD;
      let maxima: BigNumber = account.loans[market.index];
      let toRepay: BigNumber;

      if (!maxima.isZero() && maxima > minima) {
        toRepay = BigNumber.from(Math.floor(Math.random() * 1000))
          .mul(maxima.sub(minima))
          .div(1000)
          .add(minima);
        await market.token.connect(account.signer).approve(positionsManagerForAave.address, toRepay);
        console.log(account.index, 'repaid', tokenAmountToReadable(toRepay, market.token), market.name);
        await positionsManagerForAave.connect(account.signer).repay(market.aToken.address, toRepay);
        account.loans[market.index] = account.loans[market.index].sub(toRepay);
      }
      accounts[account.index] = account;
    };

    const tryGiveTokens = async (account: Account, market: Market): Promise<boolean> => {
      try {
        await giveTokensTo(market.token.address, account.address, utils.parseUnits('9999999'), market.slotPosition);
        return true;
      } catch {
        return false;
      }
    };

    const getARandomMarket = (): Market => {
      return markets[Math.floor(Math.random() * markets.length)];
    };

    const getARandomAccount = (): Account => {
      return accounts[Math.floor(Math.random() * accounts.length)];
    };

    const doWithAProbabiltyOfPercentage = async (percentage: number, callback: Function): Promise<void> => {
      if (Math.random() * 100 < percentage) {
        await callback();
      }
    };

    it('🦑🦑🦑 FOUZZZZZ 🦑🦑🦑', async () => {
      const nbOfIterations: number = 500; // config
      const initialSize: number = 50; // config
      let tempAccount: Account;

      console.log(`initializing tests with ${initialSize} suppliers`);
      for await (let i of [...Array(initialSize).keys()]) {
        tempAccount = await generateAccount();
        await supply(tempAccount, getARandomMarket());
      }

      console.log('now fuzzing 🦀');

      for await (let i of [...Array(nbOfIterations).keys()]) {
        console.log(`${i + 1}/${nbOfIterations}`);

        // await doWithAProbabiltyOfPercentage(20, async () => {
        //   tempAccount = await generateAccount();
        //   supply(tempAccount, getARandomMarket());
        // });

        await doWithAProbabiltyOfPercentage(100, async () => {
          await supply(getARandomAccount(), getARandomMarket());
        });

        await doWithAProbabiltyOfPercentage(50, async () => {
          let acc: Account = getARandomAccount();
          let mkt: Market = getARandomMarket();
          await borrow(acc, mkt);
        });

        await doWithAProbabiltyOfPercentage(50, async () => {
          let acc: Account = getARandomAccount();
          await withdraw(acc, getARandomMarket());
        });

        await doWithAProbabiltyOfPercentage(50, async () => {
          let acc: Account = getARandomAccount();
          logAccountData(acc);
          await repay(acc, getARandomMarket());
        });
      }
    });
  });
});
