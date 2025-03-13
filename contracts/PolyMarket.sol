// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

interface IVerifyOracle {
    function assertQuestion(
        address asserter,
        bytes memory claim
    ) external returns (bytes32 _assertionId);

    function getResult(bytes32 _assertionId) external view returns (bool);
}

interface IERC1155 {
    function safeMint(address account, uint256 id, uint256 amount) external;
    function balanceOf(
        address account,
        uint256 id
    ) external view returns (uint256);
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external;
    function burn(address account, uint256 id, uint256 amount) external;
}

contract PredictionMarket is ReentrancyGuard, ERC1155Holder {
    struct Market {
        string question;
        uint256 endTime;
        bool resolved;
        bool outcome;
        address creator;
        bytes32 assertionId;
        uint256 totalLiquidity;
        uint256 yesShareId;
        uint256 noShareId;
        uint256 liquidityId;
        uint256 liquidityRevenue;
    }

    mapping(uint256 => Market) public markets;

    uint256 public marketCount;
    address public admin;
    address public oracle;
    address public erc1155Token;
    uint256 public feeRate;
    IVerifyOracle public verifyOracle;

    event MarketCreated(uint256 marketId, string question, uint256 endTime);
    event LiquidityAdded(
        uint256 marketId,
        address provider,
        uint256 amount,
        uint256 liquidityShares,
        uint256 outcomeSharesYes,
        uint256 outcomeSharesNo
    );
    event SharesBought(
        uint256 marketId,
        address buyer,
        bool outcome,
        uint256 amount,
        uint256 shares
    );
    event MarketResolved(uint256 marketId, bool outcome);
    event PayoutClaimed(uint256 marketId, address user, uint256 amount);
    event WithDrawLiquidity(uint256 marketId, address user, uint256 amount);
    //errors
    error NotProvideAQuestion();
    error ShouldBeGreaterThanZero(uint256 amount);
    error InvalidAddress();
    error FeeRateMustBeLessThan100Percent();
    error MustSentEth();
    error MarketAlreadyResolved();
    error MarketClosed();
    error MarketStillOpen();
    error MarketNotResolved();
    error AssertionNotSet();
    error ZeroLiquidity();
    error InsufficientLiquidityAddition();
    error OnlyAdminAndOnwerCanCallThis();
    error MarketAlreadyAsserted();
    error NoSharesInWinningOutcome();

    //modifiers

    constructor(
        address _oracle,
        address _erc1155Token,
        uint256 _feeRate,
        address _admin
    ) {
        require(_oracle != address(0), InvalidAddress());
        require(_erc1155Token != address(0), InvalidAddress());
        require(_feeRate <= 10000, FeeRateMustBeLessThan100Percent());

        verifyOracle = IVerifyOracle(_oracle);
        erc1155Token = _erc1155Token;
        feeRate = _feeRate;
        admin = _admin;
    }

    function createMarket(string memory _question, uint256 _duration) public {
        require(bytes(_question).length > 0, NotProvideAQuestion());
        require(_duration > 0, ShouldBeGreaterThanZero(_duration));

        uint256 marketId = marketCount++;
        uint256 yesShareId = getPositionId(
            marketId,
            erc1155Token,
            msg.sender,
            true
        );
        uint256 noShareId = getPositionId(
            marketId,
            erc1155Token,
            msg.sender,
            false
        );
        uint256 liquidityId = uint256(
            keccak256(abi.encodePacked(marketId, "liquidity"))
        );

        markets[marketId] = Market({
            question: _question,
            endTime: block.timestamp + _duration,
            resolved: false,
            outcome: false,
            creator: msg.sender,
            assertionId: bytes32(0),
            totalLiquidity: 0,
            yesShareId: yesShareId,
            noShareId: noShareId,
            liquidityId: liquidityId,
            liquidityRevenue: 0
        });

        emit MarketCreated(marketId, _question, markets[marketId].endTime);
    }

    function addLiquidity(uint256 marketId) public payable nonReentrant {
        require(msg.value > 0, MustSentEth());

        Market storage market = markets[marketId];
        require(!market.resolved, MarketAlreadyResolved());
        require(block.timestamp < market.endTime, MarketClosed());

        uint256 _amount = msg.value;
        uint256 ethBalance = market.totalLiquidity;
        uint256 yesShares = IERC1155(erc1155Token).balanceOf(
            address(this),
            market.yesShareId
        );
        uint256 noShares = IERC1155(erc1155Token).balanceOf(
            address(this),
            market.noShareId
        );
        uint256 liquidityShares = IERC1155(erc1155Token).balanceOf(
            msg.sender,
            market.liquidityId
        );

        if (yesShares == 0 && noShares == 0) {
            IERC1155(erc1155Token).safeMint(
                address(this),
                market.yesShareId,
                _amount
            );
            IERC1155(erc1155Token).safeMint(
                address(this),
                market.noShareId,
                _amount
            );

            market.totalLiquidity += _amount;

            IERC1155(erc1155Token).safeMint(
                msg.sender,
                market.liquidityId,
                _amount
            );

            emit LiquidityAdded(
                marketId,
                msg.sender,
                msg.value,
                _amount,
                _amount,
                _amount
            );
        } else {
            require(ethBalance > 0, ZeroLiquidity());

            uint256 tokenYesRequired = (_amount * yesShares) / ethBalance;
            uint256 tokenNoRequired = (_amount * noShares) / ethBalance;

            require(
                tokenYesRequired > 0 && tokenNoRequired > 0,
                InsufficientLiquidityAddition()
            );

            IERC1155(erc1155Token).safeMint(
                address(this),
                market.yesShareId,
                tokenYesRequired
            );
            IERC1155(erc1155Token).safeMint(
                address(this),
                market.noShareId,
                tokenNoRequired
            );

            uint256 liquidity = (_amount * liquidityShares) / ethBalance;
            require(liquidity > 0, ZeroLiquidity());

            IERC1155(erc1155Token).safeMint(
                msg.sender,
                market.liquidityId,
                liquidity
            );
            market.totalLiquidity += _amount;

            emit LiquidityAdded(
                marketId,
                msg.sender,
                msg.value,
                liquidity,
                tokenYesRequired,
                tokenNoRequired
            );
        }
    }

    function buyShares(
        uint256 marketId,
        bool outcome
    ) public payable nonReentrant {
        require(msg.value > 0, MustSentEth());

        Market storage market = markets[marketId];
        require(!market.resolved, MarketAlreadyResolved());
        require(block.timestamp < market.endTime, MarketClosed());

        uint256 fee = (msg.value * feeRate) / 10000;
        uint256 amountAfterFee = msg.value - fee;

        market.liquidityRevenue += fee;
        uint256 shares;
        if (outcome) {
            uint256 price = getPrice(marketId, outcome);
            require(price > 0, ShouldBeGreaterThanZero(price));
            shares = (amountAfterFee * 1e18) / price;
        } else {
            uint256 price = getPrice(marketId, outcome);
            require(price > 0, ShouldBeGreaterThanZero(price));
            shares = (amountAfterFee * 1e18) / price;
        }

        uint256 shareId = outcome ? market.yesShareId : market.noShareId;
        IERC1155(erc1155Token).safeTransferFrom(
            address(this),
            msg.sender,
            shareId,
            shares,
            ""
        );

        emit SharesBought(
            marketId,
            msg.sender,
            outcome,
            amountAfterFee,
            shares
        );
    }

    function assertQuestion(
        uint256 _marketId
    ) external returns (bytes32 assertionId) {
        Market storage market = markets[_marketId];
        require(
            market.creator == msg.sender || msg.sender == admin,
            OnlyAdminAndOnwerCanCallThis()
        );
        require(block.timestamp > market.endTime, MarketStillOpen());

        require(market.assertionId == bytes32(0), MarketAlreadyAsserted());
        bytes memory claim = abi.encodePacked(market.question);

        assertionId = verifyOracle.assertQuestion(msg.sender, claim);
        market.assertionId = assertionId;
        return assertionId;
    }

    function resolveMarket(uint256 marketId) public nonReentrant {
        Market storage market = markets[marketId];
        require(
            market.creator == msg.sender || msg.sender == admin,
            OnlyAdminAndOnwerCanCallThis()
        );

        require(block.timestamp > market.endTime, MarketStillOpen());
        require(!market.resolved, MarketAlreadyResolved());
        require(market.assertionId != bytes32(0), AssertionNotSet());

        market.resolved = true;
        market.outcome = verifyOracle.getResult(market.assertionId);

        emit MarketResolved(marketId, market.outcome);
    }

    function claimPayout(uint256 marketId) public nonReentrant {
        Market storage market = markets[marketId];
        require(market.resolved, MarketNotResolved());

        uint256 shareId = market.outcome ? market.yesShareId : market.noShareId;

        uint256 userShares = IERC1155(erc1155Token).balanceOf(
            msg.sender,
            shareId
        );

        require(userShares > 0, NoSharesInWinningOutcome());

        payable(msg.sender).transfer(userShares);

        IERC1155(erc1155Token).burn(msg.sender, shareId, userShares);

        emit PayoutClaimed(marketId, msg.sender, userShares);
    }

    function getPositionId(
        uint256 marketId,
        address collateralToken,
        address creator,
        bool outcome
    ) internal pure returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        marketId,
                        collateralToken,
                        creator,
                        outcome
                    )
                )
            );
    }

    function getPrice(
        uint256 marketId,
        bool outcome
    ) public view returns (uint256) {
        Market storage market = markets[marketId];
        uint256 yesShares = IERC1155(erc1155Token).balanceOf(
            address(this),
            market.yesShareId
        );
        uint256 noShares = IERC1155(erc1155Token).balanceOf(
            address(this),
            market.noShareId
        );
        uint256 totalShares = yesShares + noShares;

        if (totalShares == 0) {
            return 1e18 / 2;
        }

        return
            outcome
                ? (noShares * 1e18) / totalShares
                : (yesShares * 1e18) / totalShares;
    }

    function withdrawLiquidity(uint256 marketId) public nonReentrant {
        // Access the market and check if the caller has liquidity tokens
        Market storage market = markets[marketId];
        uint256 LPtoken = IERC1155(erc1155Token).balanceOf(
            msg.sender,
            market.liquidityId
        );
        require(LPtoken > 0, ShouldBeGreaterThanZero(LPtoken));

        // Cache storage variables to save gas
        uint256 totalLiquidity = market.totalLiquidity;
        uint256 totalevenue = market.liquidityRevenue;

        // Ensure there is liquidity in the market
        require(totalLiquidity > 0, ShouldBeGreaterThanZero(totalLiquidity));

        // Calculate the LP's share of the revenue
        uint256 lpart = (totalevenue * LPtoken) / totalLiquidity;
        market.liquidityRevenue -= lpart;

        // Calculate the total amount to withdraw (initial liquidity + revenue share)
        uint256 amount = LPtoken + lpart;

        // Update the market's total liquidity
        market.totalLiquidity -= LPtoken;

        // Burn the LP's liquidity tokens
        IERC1155(erc1155Token).burn(msg.sender, market.liquidityId, LPtoken);

        // Transfer the total amount to the LP
        payable(msg.sender).transfer(amount);

        // Emit an event to log the withdrawal
        emit WithDrawLiquidity(marketId, msg.sender, amount);
    }

    function burnShares(uint256 marketId) public {
        Market storage market = markets[marketId];
        require(msg.sender == admin, "Only admin can burn tokens");
        require(market.resolved, MarketNotResolved());

        uint256 yesShares = IERC1155(erc1155Token).balanceOf(
            address(this),
            market.yesShareId
        );
        uint256 noShares = IERC1155(erc1155Token).balanceOf(
            address(this),
            market.noShareId
        );

        require(yesShares > 0 || noShares > 0, "No shares to burn");

        if (yesShares > 0) {
            IERC1155(erc1155Token).burn(
                address(this),
                market.yesShareId,
                yesShares
            );
        }
        if (noShares > 0) {
            IERC1155(erc1155Token).burn(
                address(this),
                market.noShareId,
                noShares
            );
        }
    }
}
