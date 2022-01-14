import * as dotenv from 'dotenv';
dotenv.config({ path: './.env.local' });
import hre, { ethers } from 'hardhat';
import { Signer, Contract } from 'ethers';
import { expect } from 'chai';

describe('DoubleLinkedList Contract', () => {
  let snapshotId: number;
  let testDoubleLinkedList: Contract;
  let signers: Signer[];
  let firstTenAccounts: string[];
  let lastTenAccounts: string[];
  const accounts: string[] = [];
  const NMAX = 50;

  const initialize = async () => {
    signers = await ethers.getSigners();
    for (const signer of signers) {
      accounts.push(await signer.getAddress());
    }
    firstTenAccounts = accounts.slice(0, 10);
    lastTenAccounts = accounts.slice(10, 20);

    // Deploy TestDoubleLinkedList
    const TestDoubleLinkedList = await ethers.getContractFactory('TestDoubleLinkedList');
    testDoubleLinkedList = await TestDoubleLinkedList.deploy();
    await testDoubleLinkedList.deployed();
  };

  before(initialize);

  beforeEach(async () => {
    snapshotId = await hre.network.provider.send('evm_snapshot', []);
  });

  afterEach(async () => {
    await hre.network.provider.send('evm_revert', [snapshotId]);
  });

  describe('Test DoubleLinkedList', () => {
    it('Should insert one single account', async () => {
      await testDoubleLinkedList.insertSorted(accounts[0], 1, NMAX);
      expect(await testDoubleLinkedList.getHead()).to.equal(accounts[0]);
      expect(await testDoubleLinkedList.getTail()).to.equal(accounts[0]);
      expect(await testDoubleLinkedList.getValueOf(accounts[0])).to.equal(1);
      expect(await testDoubleLinkedList.getPrev(accounts[0])).to.equal(ethers.constants.AddressZero);
      expect(await testDoubleLinkedList.getNext(accounts[0])).to.equal(ethers.constants.AddressZero);
    });

    it('Should remove one single account', async () => {
      await testDoubleLinkedList.insertSorted(accounts[0], 1, NMAX);
      await testDoubleLinkedList.remove(accounts[0]);
      expect(await testDoubleLinkedList.getHead()).to.equal(ethers.constants.AddressZero);
      expect(await testDoubleLinkedList.getTail()).to.equal(ethers.constants.AddressZero);
      expect(await testDoubleLinkedList.getValueOf(accounts[0])).to.equal(0);
      expect(await testDoubleLinkedList.getPrev(accounts[0])).to.equal(ethers.constants.AddressZero);
      expect(await testDoubleLinkedList.getNext(accounts[0])).to.equal(ethers.constants.AddressZero);
    });

    it('Should insert 2 accounts', async () => {
      await testDoubleLinkedList.insertSorted(accounts[0], 2, NMAX);
      await testDoubleLinkedList.insertSorted(accounts[1], 1, NMAX);
      expect(await testDoubleLinkedList.getHead()).to.equal(accounts[0]);
      expect(await testDoubleLinkedList.getTail()).to.equal(accounts[1]);
      expect(await testDoubleLinkedList.getValueOf(accounts[0])).to.equal(2);
      expect(await testDoubleLinkedList.getValueOf(accounts[1])).to.equal(1);
      expect(await testDoubleLinkedList.getPrev(accounts[0])).to.equal(ethers.constants.AddressZero);
      expect(await testDoubleLinkedList.getNext(accounts[0])).to.equal(accounts[1]);
      expect(await testDoubleLinkedList.getPrev(accounts[1])).to.equal(accounts[0]);
      expect(await testDoubleLinkedList.getNext(accounts[1])).to.equal(ethers.constants.AddressZero);
    });

    it('Should insert 3 accounts', async () => {
      await testDoubleLinkedList.insertSorted(accounts[0], 3, NMAX);
      await testDoubleLinkedList.insertSorted(accounts[1], 2, NMAX);
      await testDoubleLinkedList.insertSorted(accounts[2], 1, NMAX);
      expect(await testDoubleLinkedList.getHead()).to.equal(accounts[0]);
      expect(await testDoubleLinkedList.getTail()).to.equal(accounts[2]);
      expect(await testDoubleLinkedList.getValueOf(accounts[0])).to.equal(3);
      expect(await testDoubleLinkedList.getValueOf(accounts[1])).to.equal(2);
      expect(await testDoubleLinkedList.getValueOf(accounts[2])).to.equal(1);
      expect(await testDoubleLinkedList.getPrev(accounts[0])).to.equal(ethers.constants.AddressZero);
      expect(await testDoubleLinkedList.getNext(accounts[0])).to.equal(accounts[1]);
      expect(await testDoubleLinkedList.getPrev(accounts[1])).to.equal(accounts[0]);
      expect(await testDoubleLinkedList.getNext(accounts[1])).to.equal(accounts[2]);
      expect(await testDoubleLinkedList.getPrev(accounts[2])).to.equal(accounts[1]);
      expect(await testDoubleLinkedList.getNext(accounts[2])).to.equal(ethers.constants.AddressZero);
    });

    it('Should remove 1 account over 2', async () => {
      await testDoubleLinkedList.insertSorted(accounts[0], 2, NMAX);
      await testDoubleLinkedList.insertSorted(accounts[1], 1, NMAX);
      await testDoubleLinkedList.remove(accounts[0]);
      expect(await testDoubleLinkedList.getHead()).to.equal(accounts[1]);
      expect(await testDoubleLinkedList.getTail()).to.equal(accounts[1]);
      expect(await testDoubleLinkedList.getValueOf(accounts[0])).to.equal(0);
      expect(await testDoubleLinkedList.getValueOf(accounts[1])).to.equal(1);
      expect(await testDoubleLinkedList.getNext(accounts[1])).to.equal(ethers.constants.AddressZero);
      expect(await testDoubleLinkedList.getPrev(accounts[1])).to.equal(ethers.constants.AddressZero);
    });

    it('Should remove both accounts', async () => {
      await testDoubleLinkedList.insertSorted(accounts[0], 2, NMAX);
      await testDoubleLinkedList.insertSorted(accounts[1], 1, NMAX);
      await testDoubleLinkedList.remove(accounts[0]);
      await testDoubleLinkedList.remove(accounts[1]);
      expect(await testDoubleLinkedList.getHead()).to.equal(ethers.constants.AddressZero);
      expect(await testDoubleLinkedList.getTail()).to.equal(ethers.constants.AddressZero);
    });

    it('Should insert 3 accounts and remove them', async () => {
      await testDoubleLinkedList.insertSorted(accounts[0], 3, NMAX);
      await testDoubleLinkedList.insertSorted(accounts[1], 2, NMAX);
      await testDoubleLinkedList.insertSorted(accounts[2], 1, NMAX);
      expect(await testDoubleLinkedList.getHead()).to.equal(accounts[0]);
      expect(await testDoubleLinkedList.getTail()).to.equal(accounts[2]);

      // Remove account 0
      await testDoubleLinkedList.remove(accounts[0]);
      expect(await testDoubleLinkedList.getHead()).to.equal(accounts[1]);
      expect(await testDoubleLinkedList.getTail()).to.equal(accounts[2]);
      expect(await testDoubleLinkedList.getPrev(accounts[1])).to.equal(ethers.constants.AddressZero);
      expect(await testDoubleLinkedList.getNext(accounts[1])).to.equal(accounts[2]);
      expect(await testDoubleLinkedList.getPrev(accounts[2])).to.equal(accounts[1]);
      expect(await testDoubleLinkedList.getNext(accounts[2])).to.equal(ethers.constants.AddressZero);

      // Remove account 1
      await testDoubleLinkedList.remove(accounts[1]);
      expect(await testDoubleLinkedList.getHead()).to.equal(accounts[2]);
      expect(await testDoubleLinkedList.getTail()).to.equal(accounts[2]);
      expect(await testDoubleLinkedList.getPrev(accounts[2])).to.equal(ethers.constants.AddressZero);
      expect(await testDoubleLinkedList.getNext(accounts[2])).to.equal(ethers.constants.AddressZero);

      // Remove account 2
      await testDoubleLinkedList.remove(accounts[2]);
      expect(await testDoubleLinkedList.getHead()).to.equal(ethers.constants.AddressZero);
      expect(await testDoubleLinkedList.getTail()).to.equal(ethers.constants.AddressZero);
    });

    it('Should insert accounts all sorted', async () => {
      const value = 50;
      for (let i = 0; i < accounts.length; i++) {
        await testDoubleLinkedList.insertSorted(accounts[i], value - i, NMAX);
      }
      expect(await testDoubleLinkedList.getHead()).to.equal(accounts[0]);
      expect(await testDoubleLinkedList.getTail()).to.equal(accounts[accounts.length - 1]);
      let nextAccount = accounts[0];
      for (let i = 0; i < accounts.length - 1; i++) {
        nextAccount = await testDoubleLinkedList.getNext(nextAccount);
        expect(nextAccount).to.equal(accounts[i + 1]);
      }
      let prevAccount = accounts[accounts.length - 1];
      for (let i = 0; i < accounts.length - 1; i++) {
        prevAccount = await testDoubleLinkedList.getPrev(prevAccount);
        expect(prevAccount).to.equal(accounts[accounts.length - i - 2]);
      }
    });

    it('Should remove all sorted accounts', async () => {
      const value = 50;
      for (let i = 0; i < accounts.length; i++) {
        await testDoubleLinkedList.insertSorted(accounts[i], value - i, NMAX);
      }
      for (let i = 0; i < accounts.length; i++) {
        await testDoubleLinkedList.remove(accounts[i]);
      }
      expect(await testDoubleLinkedList.getHead()).to.equal(ethers.constants.AddressZero);
      expect(await testDoubleLinkedList.getTail()).to.equal(ethers.constants.AddressZero);
    });

    it('Should insert account sorted at the beginning until NMAX', async () => {
      const value = 50;
      const newNMAX = 10;

      // Add first 10 accounts with decreasing value
      for (let i = 0; i < firstTenAccounts.length; i++) {
        await testDoubleLinkedList.insertSorted(firstTenAccounts[i], value - i, newNMAX);
      }
      expect(await testDoubleLinkedList.getHead()).to.equal(firstTenAccounts[0]);
      expect(await testDoubleLinkedList.getTail()).to.equal(firstTenAccounts[firstTenAccounts.length - 1]);
      let nextAccount = firstTenAccounts[0];
      for (let i = 0; i < firstTenAccounts.length - 1; i++) {
        nextAccount = await testDoubleLinkedList.getNext(nextAccount);
        expect(nextAccount).to.equal(firstTenAccounts[i + 1]);
      }
      let prevAccount = firstTenAccounts[firstTenAccounts.length - 1];
      for (let i = 0; i < firstTenAccounts.length - 1; i++) {
        prevAccount = await testDoubleLinkedList.getPrev(prevAccount);
        expect(prevAccount).to.equal(firstTenAccounts[firstTenAccounts.length - i - 2]);
      }

      // Add last 10 accounts at the same value
      for (let i = 0; i < lastTenAccounts.length; i++) {
        await testDoubleLinkedList.insertSorted(lastTenAccounts[i], 10, newNMAX);
      }
      expect(await testDoubleLinkedList.getHead()).to.equal(firstTenAccounts[0]);
      expect(await testDoubleLinkedList.getTail()).to.equal(lastTenAccounts[lastTenAccounts.length - 1]);

      nextAccount = accounts[0];
      for (let i = 0; i < accounts.length - 1; i++) {
        nextAccount = await testDoubleLinkedList.getNext(nextAccount);
        expect(nextAccount).to.equal(accounts[i + 1]);
      }
      prevAccount = accounts[accounts.length - 1];
      for (let i = 0; i < accounts.length - 1; i++) {
        prevAccount = await testDoubleLinkedList.getPrev(prevAccount);
        expect(prevAccount).to.equal(accounts[accounts.length - i - 2]);
      }
    });
  });
});
