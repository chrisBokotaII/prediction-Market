import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";

describe("Lock", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployOneYearLockFixture() {
    const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
    const ONE_GWEI = 1_000_000_000;

    const lockedAmount = ONE_GWEI;
    const unlockTime = (await time.latest()) + ONE_YEAR_IN_SECS;

    // Contracts are deployed using the first signer/account by default
    const [owner, otherAccount, signer1, signer2, signer3, signer4, signer5] =
      await hre.ethers.getSigners();

    // Deploying the MultiSigWallet contract
    const MultiSigWallet = await hre.ethers.getContractFactory(
      "MultiSigWallet"
    );
    const multiSigWallet = await MultiSigWallet.deploy([
      signer1.address,
      signer2.address,
      signer3.address,
      signer4.address,
      signer5.address,
    ]);

    // Deploying the OptimisticOracleV3 contract
    const OptimisticOracleV3 = await hre.ethers.getContractFactory(
      "OptimisticOracleV3"
    );
    const optimisticOracleV3 = await OptimisticOracleV3.deploy(
      multiSigWallet.target
    );
    // Deploying the VerifyOracle contract

    const verifyOracle = await hre.ethers.getContractFactory("VerifyOracle");
    const verifyOracleContract = await verifyOracle.deploy(
      optimisticOracleV3.target
    );
    return {
      optimisticOracleV3,
      verifyOracleContract,
      owner,
      otherAccount,
      signer1,
      signer2,
      signer3,
      signer4,
      signer5,
      lockedAmount,
      unlockTime,
      multiSigWallet,
    };
  }
  async function assertQuestion(question: string) {
    const { verifyOracleContract, owner } = await loadFixture(
      deployOneYearLockFixture
    );
    const bytes32Question = hre.ethers.toUtf8Bytes(question);
    await verifyOracleContract
      .connect(owner)
      .assertQuestion(owner.address, bytes32Question);
    const Fillter = verifyOracleContract.filters.AssertionCreated();
    const events = await verifyOracleContract.queryFilter(Fillter);
    const event = events[0];
    const args = event.args;
    const questionId = args[0];
    const assertor = args[1];
    return {
      questionId,
      assertor,
    };
  }

  describe("Deployment", function () {
    it("Should set the address", async function () {
      const { optimisticOracleV3, verifyOracleContract, multiSigWallet } =
        await loadFixture(deployOneYearLockFixture);

      expect(optimisticOracleV3.target).to.be.properAddress;
      expect(verifyOracleContract.target).to.be.properAddress;
      expect(multiSigWallet.target).to.be.properAddress;
      expect(await verifyOracleContract.oracle()).to.be.equal(
        optimisticOracleV3.target
      );
    });
  });

  describe("Assertions", function () {
    it("should assert a question", async function () {
      const {
        owner,
        verifyOracleContract,
        multiSigWallet,
        optimisticOracleV3,
        signer1,
        signer2,
        signer3,
        signer4,
        signer5,
      } = await loadFixture(deployOneYearLockFixture);
      const question = "trump is the president of the US";
      const questionId = await assertQuestion(question);
      const Fillter = multiSigWallet.filters.TransactionCreated();
      const events = await multiSigWallet.queryFilter(Fillter);
      const event = events[0];
      const args = event.args;
      const transactionId = args[0];
      const txID = args[1];
      const claim = args[2];
      const transaction = await multiSigWallet.get_Transaction(transactionId);
      console.log(transaction);
      expect(txID).to.be.equal(questionId.questionId);
      expect(transaction[0]).to.be.equal(questionId.questionId);
      expect(transaction[1]).to.be.equal(claim);
      expect(transaction[2]).to.be.equal(false);
      expect(transaction[5]).to.be.equal(optimisticOracleV3.target);

      //signers sign the transaction
      await multiSigWallet.connect(signer1).signTransaction(transactionId);
      await multiSigWallet.connect(signer2).signTransaction(transactionId);
      await multiSigWallet.connect(signer3).signTransaction(transactionId);
      await multiSigWallet.connect(signer4).signTransaction(transactionId);
      await multiSigWallet.connect(signer5).signTransaction(transactionId);
      const transactionAfter = await multiSigWallet.get_Transaction(
        transactionId
      );
      await time.increase(60 * 60 * 24 * 7);
      //execute tx
      await multiSigWallet.connect(owner).executeTransaction(transactionId);
      const transactionAfterExecution = await multiSigWallet.get_Transaction(
        transactionId
      );
      expect(transactionAfterExecution[2]).to.be.equal(true);
      const result = await verifyOracleContract.getResult(
        questionId.questionId
      );
      expect(result).to.be.equal(true);
    });
  });
});
