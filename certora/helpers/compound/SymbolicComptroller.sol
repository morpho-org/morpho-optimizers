// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./SymbolicOracle.sol";
import "./SymbolicCToken.sol";

// TODO: symbolic behavior

contract SymbolicComptroller {
    /// STORAGE ///

    SymbolicOracle public oracle;
    uint256 public closeFactorMantissa;
    uint256 public liquidationIncentiveMantissa;
    uint256 public maxAssets;
    mapping(address => SymbolicCToken[]) public accountAssets;

    struct Market {
        bool isListed;
        uint256 collateralFactorMantissa;
        mapping(address => bool) accountMembership;
        bool isComped;
    }

    mapping(address => Market) public markets;
    address public pauseGuardian;
    bool public _mintGuardianPaused;
    bool public _borrowGuardianPaused;
    bool public transferGuardianPaused;
    bool public seizeGuardianPaused;
    mapping(address => bool) public mintGuardianPaused;
    mapping(address => bool) public borrowGuardianPaused;

    struct CompMarketState {
        uint224 index;
        uint32 block;
    }

    CToken[] public allMarkets;
    uint256 public compRate;
    mapping(address => uint256) public compSpeeds;
    mapping(address => CompMarketState) public symbolicCompSupplyState;
    mapping(address => CompMarketState) public symbolicCompBorrowState;
    mapping(address => mapping(address => uint256)) public compSupplierIndex;
    mapping(address => mapping(address => uint256)) public compBorrowerIndex;
    mapping(address => uint256) public compAccrued;
    address public borrowCapGuardian;
    mapping(address => uint256) public borrowCaps;
    mapping(address => uint256) public compContributorSpeeds;
    mapping(address => uint256) public lastContributorBlock;

    // solhint-disable-next-line
    struct marketsStruct {
        bool b1;
        uint256 val;
        bool b2;
    }
    mapping(address => marketsStruct) public marketsRet;

    /// FUNCTIONS ///

    mapping(address => ICToken[]) public getAssetsInRes;

    function getAssetsIn(address account) external view returns (ICToken[] memory) {}

    mapping(address => mapping(address => bool)) public checkMembershipRet;

    function checkMembership(address account, address cToken)
        external
        view
        override
        returns (bool)
    {
        return checkMembershipRet[cToken][account];
    }

    mapping(address => uint256[]) public enterMarketsRet;

    function enterMarkets(address[] calldata cTokens) external override returns (uint256[] memory) {
        return enterMarketsRet[cTokens[0]];
    }

    mapping(address => uint256) public exitMarketRet;

    function exitMarket(address cToken) external override returns (uint256) {
        return exitMarketRet[cToken];
    }

    // these nested mappings aren't very pretty, perhaps there is a better way to do this?
    mapping(address => mapping(address => mapping(uint256 => uint256))) public mintAllowedRet;

    function mintAllowed(
        address cToken,
        address minter,
        uint256 mintAmount
    ) external override returns (uint256) {
        return mintAllowedRet[cToken][minter][mintAmount];
    }

    function mintVerify(
        address, // cToken
        address, // minter
        uint256 mintAmount,
        uint256 // mintTokens
    ) external override {
        // solhint-disable-next-line
        uint256 val = mintAmount;
    }

    mapping(address => mapping(address => mapping(uint256 => uint256))) public redeemAllowedRet;

    function redeemAllowed(
        address cToken,
        address redeemer,
        uint256 redeemTokens
    ) external override returns (uint256) {
        return redeemAllowedRet[cToken][redeemer][redeemTokens];
    }

    function redeemVerify(
        address, // cToken
        address, // redeemer
        uint256 redeemAmount,
        uint256 // redeemTokens
    ) external override {
        // solhint-disable-next-line
        uint256 val = redeemAmount;
    }

    mapping(address => mapping(address => mapping(uint256 => uint256))) public borrowAllowedRet;

    function borrowAllowed(
        address cToken,
        address borrower,
        uint256 borrowAmount
    ) external override returns (uint256) {
        return borrowAllowedRet[cToken][borrower][borrowAmount];
    }

    function borrowVerify(
        address,
        address,
        uint256 borrowAmount
    ) external override {
        // solhint-disable-next-line
        uint256 val = borrowAmount;
    }

    mapping(address => mapping(address => mapping(address => mapping(uint256 => uint256))))
        public repayBorrowAllowedRet;

    function repayBorrowAllowed(
        address cToken,
        address payer,
        address borrower,
        uint256 repayAmount
    ) external override returns (uint256) {
        return repayBorrowAllowedRet[cToken][payer][borrower][repayAmount];
    }

    function repayBorrowVerify(
        address, // cToken
        address, // payer
        address, // borrower
        uint256 repayAmount,
        uint256 // borrowerIndex
    ) external override {
        // solhint-disable-next-line
        uint256 val = repayAmount;
    }

    // solhint-disable-next-line
    struct liquidateBorrowAllowedParams {
        address cTokenBorrowed;
        address cTokenCollateral;
        address liquidator;
        address borrower;
        uint256 repayAmount;
    }
    mapping(address => mapping(address => mapping(address => mapping(address => mapping(uint256 => uint256)))))
        public liquidateBorrowAllowedRet;

    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external override returns (uint256) {
        return
            liquidateBorrowAllowedRet[cTokenBorrowed][cTokenCollateral][liquidator][borrower][
                repayAmount
            ];
    }

    function liquidateBorrowVerify(
        address, // cTokenBorrowed
        address, // cTokenCollateral
        address, // liquidator
        address, // borrower
        uint256, // repayAmount
        uint256 seizeTokens
    ) external override {
        // solhint-disable-next-line
        uint256 val = seizeTokens;
    }

    // solhint-disable-next-line
    struct seizeAllowedParams {
        address cTokenCollateral;
        address cTokenBorrowed;
        address liquidator;
        address borrower;
        uint256 seizeTokens;
    }
    mapping(address => mapping(address => mapping(address => mapping(address => mapping(uint256 => uint256)))))
        public seizeAllowedRet;

    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external override returns (uint256) {
        return seizeAllowedRet[cTokenCollateral][cTokenBorrowed][liquidator][borrower][seizeTokens];
    }

    function seizeVerify(
        address, // cTokenCollateral
        address, // cTokenBorrowed
        address, // liquidator
        address, // borrower
        uint256 seizeTokens
    ) external override {
        // solhint-disable-next-line
        uint256 val = seizeTokens;
    }

    // solhint-disable-next-line
    struct transferAllowedParams {
        address cToken;
        address src;
        address dst;
        uint256 transferTokens;
    }
    mapping(address => mapping(address => mapping(address => mapping(uint256 => uint256))))
        public transferAllowedRet;

    function transferAllowed(
        address cToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external override returns (uint256) {
        return transferAllowedRet[cToken][src][dst][transferTokens];
    }

    function transferVerify(
        address, // cToken
        address, // src
        address, // dst
        uint256 transferTokens
    ) external override {
        // solhint-disable-next-line
        uint256 val = transferTokens;
    }

    /*** Liquidity/Liquidation Calculations ***/

    mapping(address => mapping(address => mapping(uint256 => uint256)))
        public liquidateCalculateSeizeTokens1;
    mapping(address => mapping(address => mapping(uint256 => uint256)))
        public liquidateCalculateSeizeTokens2;

    function liquidateCalculateSeizeTokens(
        address cTokenBorrowed,
        address cTokenCollateral,
        uint256 repayAmount
    ) external view override returns (uint256, uint256) {
        return (
            liquidateCalculateSeizeTokens1[cTokenBorrowed][cTokenCollateral][repayAmount],
            liquidateCalculateSeizeTokens2[cTokenBorrowed][cTokenCollateral][repayAmount]
        );
    }

    mapping(address => uint256) public getAccountLiquidity1;
    mapping(address => uint256) public getAccountLiquidity2;
    mapping(address => uint256) public getAccountLiquidity3;

    function getAccountLiquidity(address account)
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (
            getAccountLiquidity1[account],
            getAccountLiquidity2[account],
            getAccountLiquidity3[account]
        );
    }

    struct GHALParams {
        address a1;
        address a2;
        uint256 v1;
        uint256 v2;
    }
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => uint256))))
        public getHypotheticalAccountLiquidity1;
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => uint256))))
        public getHypotheticalAccountLiquidity2;
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => uint256))))
        public getHypotheticalAccountLiquidity3;

    function getHypotheticalAccountLiquidity(
        address a1,
        address a2,
        uint256 v1,
        uint256 v2
    )
        external
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (
            getHypotheticalAccountLiquidity1[a1][a2][v1][v2],
            getHypotheticalAccountLiquidity2[a1][a2][v1][v2],
            getHypotheticalAccountLiquidity3[a1][a2][v1][v2]
        );
    }
}
