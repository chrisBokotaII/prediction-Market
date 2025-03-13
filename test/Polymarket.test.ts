import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre from "hardhat";

describe("PolyMarket", function () {
  // Fixture to deploy contracts and initialize variables
  async function deployContractsFixture() {
    const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
    const ONE_GWEI = 1_000_000_000;

    const lockedAmount = ONE_GWEI;
    const unlockTime = (await time.latest()) + ONE_YEAR_IN_SECS;

    // Get signers (accounts)
    const [owner, otherAccount, signer1, signer2, signer3, signer4, signer5] =
      await hre.ethers.getSigners();

    // Deploy MultiSigWallet
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

    // Deploy OptimisticOracleV3
    const OptimisticOracleV3 = await hre.ethers.getContractFactory(
      "OptimisticOracleV3"
    );
    const optimisticOracleV3 = await OptimisticOracleV3.deploy(
      multiSigWallet.target
    );

    // Deploy VerifyOracle
    const Oracle = await hre.ethers.getContractFactory("VerifyOracle");
    const oracle = await Oracle.deploy(optimisticOracleV3.target);

    // Deploy Token
    const Token = await hre.ethers.getContractFactory("Token");
    const token = await Token.deploy();

    // Deploy PredictionMarket
    const PolyMarket = await hre.ethers.getContractFactory("PredictionMarket");
    const polyMarket = await PolyMarket.deploy(
      oracle.target,
      token.target,
      500, // Fee percentage
      owner.address
    );

    return {
      multiSigWallet,
      optimisticOracleV3,
      oracle,
      token,
      polyMarket,
      owner,
      signer1,
      signer2,
      signer3,
      signer4,
      signer5,
    };
  }

  describe("Deployment", function () {
    it("should deploy all contracts correctly", async function () {
      const { multiSigWallet, optimisticOracleV3, oracle, token, polyMarket } =
        await loadFixture(deployContractsFixture);

      // Check if contracts are deployed and have valid addresses
      expect(multiSigWallet.target).to.be.properAddress;
      expect(optimisticOracleV3.target).to.be.properAddress;
      expect(oracle.target).to.be.properAddress;
      expect(token.target).to.be.properAddress;
      expect(polyMarket.target).to.be.properAddress;
    });
  });

  describe("Prediction Market", function () {
    it("should create a market, add liquidity, buy shares, resolve, and allow payouts", async function () {
      const {
        polyMarket,
        token,
        oracle,
        multiSigWallet,
        owner,
        signer1,
        signer2,
        signer3,
        signer4,
        signer5,
      } = await loadFixture(deployContractsFixture);

      // Define market parameters
      const question = "Is the sky blue?";
      const marketDuration = 60 * 60 * 1000; // 1 hour in milliseconds
      const liquidityAmount = hre.ethers.parseEther("100"); // 100 ETH
      const sharePurchaseAmount = hre.ethers.parseEther("10"); // 10 ETH

      // Step 1: Create a new market
      await polyMarket.createMarket(question, marketDuration);

      // Fetch the MarketCreated event
      const marketCreatedFilter = polyMarket.filters.MarketCreated();
      const marketCreatedEvents = await polyMarket.queryFilter(
        marketCreatedFilter
      );
      const marketCreatedEvent = marketCreatedEvents[0];
      const [marketId, marketQuestion] = marketCreatedEvent.args;

      // Verify the market question
      expect(marketQuestion).to.equal(question);

      // Step 2: Add liquidity to the market
      await polyMarket.connect(signer1).addLiquidity(marketId, {
        value: liquidityAmount,
      });

      // Fetch market details
      const market = await polyMarket.markets(marketId);
      const yesTokenId = market[7];
      const noTokenId = market[8];

      // Get initial token balances
      const initialYesBalance = await token.balanceOf(
        polyMarket.target,
        yesTokenId
      );
      const initialNoBalance = await token.balanceOf(
        polyMarket.target,
        noTokenId
      );

      console.log("Initial Yes Token Balance:", initialYesBalance.toString());
      console.log("Initial No Token Balance:", initialNoBalance.toString());

      // Get initial share prices
      const initialYesPrice = await polyMarket.getPrice(marketId, true);
      const initialNoPrice = await polyMarket.getPrice(marketId, false);

      console.log(
        "Initial Yes Share Price:",
        hre.ethers.formatEther(initialYesPrice)
      );
      console.log(
        "Initial No Share Price:",
        hre.ethers.formatEther(initialNoPrice)
      );

      // Step 3: Buy shares (Yes and No)
      await polyMarket.buyShares(marketId, true, {
        value: sharePurchaseAmount,
      });
      await polyMarket
        .connect(signer2)
        .buyShares(marketId, true, { value: sharePurchaseAmount });
      await polyMarket
        .connect(signer3)
        .buyShares(marketId, true, { value: sharePurchaseAmount });
      await polyMarket
        .connect(signer4)
        .buyShares(marketId, true, { value: sharePurchaseAmount });
      await polyMarket
        .connect(signer5)
        .buyShares(marketId, false, { value: sharePurchaseAmount });

      // Get updated token balances
      const updatedYesBalance = await token.balanceOf(
        polyMarket.target,
        yesTokenId
      );
      const updatedNoBalance = await token.balanceOf(
        polyMarket.target,
        noTokenId
      );

      console.log("Updated Yes Token Balance:", updatedYesBalance.toString());
      console.log("Updated No Token Balance:", updatedNoBalance.toString());

      // Get updated share prices
      const updatedYesPrice = await polyMarket.getPrice(marketId, true);
      const updatedNoPrice = await polyMarket.getPrice(marketId, false);

      console.log(
        "Updated Yes Share Price:",
        hre.ethers.formatEther(updatedYesPrice)
      );
      console.log(
        "Updated No Share Price:",
        hre.ethers.formatEther(updatedNoPrice)
      );

      // Step 4: Fast-forward time to after the market duration
      await time.increase(7 * 60 * 60 * 1000); // 7 hours

      // Step 5: Assert the question to resolve the market
      await polyMarket.assertQuestion(marketId);

      // Fetch the AssertionCreated event from the oracle
      const assertionCreatedFilter = oracle.filters.AssertionCreated();
      const assertionCreatedEvents = await oracle.queryFilter(
        assertionCreatedFilter
      );
      const assertionCreatedEvent = assertionCreatedEvents[0];
      const [questionId, assertor] = assertionCreatedEvent.args;

      console.log("Assertion Created:", assertionCreatedEvent.args);

      // Step 6: Fetch the TransactionCreated event from the MultiSigWallet
      const transactionCreatedFilter =
        multiSigWallet.filters.TransactionCreated();
      const transactionCreatedEvents = await multiSigWallet.queryFilter(
        transactionCreatedFilter
      );
      const transactionCreatedEvent = transactionCreatedEvents[0];
      const transactionId = transactionCreatedEvent.args[0];

      console.log("Transaction Created:", transactionCreatedEvent.args);

      // Step 7: Sign the transaction with all signers
      await multiSigWallet.connect(signer1).signTransaction(transactionId);
      await multiSigWallet.connect(signer2).signTransaction(transactionId);
      await multiSigWallet.connect(signer3).signTransaction(transactionId);
      await multiSigWallet.connect(signer4).signTransaction(transactionId);
      await multiSigWallet.connect(signer5).signTransaction(transactionId);

      // Step 8: Fast-forward time to allow execution
      await time.increase(60 * 60 * 24 * 7); // 7 days

      // Step 9: Execute the transaction
      await multiSigWallet.connect(owner).executeTransaction(transactionId);

      // Fetch the transaction details
      const transactionDetails = await multiSigWallet.get_Transaction(
        transactionId
      );
      console.log("Transaction Details:", transactionDetails);

      // Step 10: Fetch the result from the oracle
      const result = await oracle.getResult(questionId);
      console.log("Oracle Result:", result);

      // Step 11: Resolve the market
      await polyMarket.connect(owner).resolveMarket(marketId);

      // Step 12: Claim payouts
      const balanceBefore = await hre.ethers.provider.getBalance(
        signer4.address
      );
      console.log("Balance Before:", hre.ethers.formatEther(balanceBefore));

      await polyMarket.connect(signer4).claimPayout(marketId);
      await polyMarket.connect(signer3).claimPayout(marketId);
      await polyMarket.connect(signer2).claimPayout(marketId);

      const claimPayoutFilter = polyMarket.filters.PayoutClaimed();
      const claimPayoutEvents = await polyMarket.queryFilter(claimPayoutFilter);
      const claimPayoutEvent = claimPayoutEvents[0];
      const [id, claimer, payout] = claimPayoutEvent.args;

      console.log("Claimer:", claimer);
      console.log("Payout:", hre.ethers.formatEther(payout));

      const balanceAfter = await hre.ethers.provider.getBalance(
        signer4.address
      );
      console.log("Balance After:", hre.ethers.formatEther(balanceAfter));

      expect(balanceAfter).to.be.gt(balanceBefore);

      // Step 13: Revert when trying to claim again
      await expect(polyMarket.connect(signer4).claimPayout(marketId)).to.be
        .reverted;

      // Step 14: Revert when trying to claim on the losing side
      await expect(polyMarket.connect(signer5).claimPayout(marketId)).to.be
        .reverted;

      // Step 15: Withdraw remaining liquidity
      const feesbefore = await polyMarket.markets(marketId);
      console.log("Fees:", feesbefore[10].toString());
      console.log("market before", market);
      await polyMarket.connect(signer1).withdrawLiquidity(marketId);
      const liquidityBalance = await hre.ethers.provider.getBalance(
        polyMarket.target
      );
      console.log(
        "Liquidity Balance:",
        hre.ethers.formatEther(liquidityBalance)
      );
      const fees = await polyMarket.markets(marketId);
      const marketAfter = await polyMarket.markets(marketId);
      console.log("Fees:", fees[10].toString());
      console.log("market after", marketAfter);

      // Step 16: Burn remaining tokens
      await polyMarket.connect(owner).burnShares(marketId);

      // Step 17: Get outcome balances after burning
      const yesOutcomeBalance = await token.balanceOf(
        polyMarket.target,
        yesTokenId
      );
      const noOutcomeBalance = await token.balanceOf(
        polyMarket.target,
        noTokenId
      );

      console.log("Outcome Yes Balance:", yesOutcomeBalance.toString());
      console.log("Outcome No Balance:", noOutcomeBalance.toString());

      expect(yesOutcomeBalance).to.be.equal(0);
      expect(noOutcomeBalance).to.be.equal(0);
    });
  });
});
