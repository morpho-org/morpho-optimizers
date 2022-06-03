pragma solidity ^0.8.0;

/// WARNING: do not use in production ///

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./interfaces/INonfungiblePositionManager.sol";

import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

contract UniswapV3PoolCreator is IERC721Receiver {
    /// @notice Represents the deposit of an NFT
    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    /// @dev deposits[tokenId] => Deposit
    mapping(uint256 => Deposit) public deposits;

    int24 internal constant MIN_TICK = -887272;
    /// @dev The maximum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**128
    int24 internal constant MAX_TICK = -MIN_TICK;

    IUniswapV3Factory public uniswapFactory =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    INonfungiblePositionManager public nonFungiblePositionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address public WETH9; // Intermediate token address.
    uint24 public constant POOL_FEE = 3000;

    // For this example, we will provide equal amounts of liquidity in both assets.
    // Providing liquidity in both assets means liquidity will be earning fees and is considered in-range.
    uint256 public amountToMint = 1000e18;

    constructor() {
        WETH9 = nonFungiblePositionManager.WETH9();
    }

    function createPoolAndMintPosition(address _token0) external {
        uint160 sqrt_ = 1e27;

        address token0 = _token0;
        address token1 = WETH9;
        if (token1 < token0) {
            // createAndInitializePoolIfNecessary requires that token 0 address < token 1 address
            (token0, token1) = (token1, token0);
        }
        nonFungiblePositionManager.createAndInitializePoolIfNecessary(
            token0,
            token1,
            POOL_FEE,
            sqrt_
        );

        mintNewPosition(_token0);
    }

    function getAdjustedTicks(int24 ticks) internal view returns (int24) {
        int24 tickSpacing = uniswapFactory.feeAmountTickSpacing(POOL_FEE);
        return (ticks / tickSpacing) * tickSpacing;
    }

    function mintNewPosition(address _token0)
        public
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        // Approve the position manager
        TransferHelper.safeApprove(_token0, address(nonFungiblePositionManager), amountToMint);
        TransferHelper.safeApprove(WETH9, address(nonFungiblePositionManager), amountToMint);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
        .MintParams({
            token0: _token0 < WETH9 ? _token0 : WETH9,
            token1: _token0 < WETH9 ? WETH9 : _token0,
            fee: POOL_FEE,
            tickLower: getAdjustedTicks(MIN_TICK),
            tickUpper: getAdjustedTicks(MAX_TICK),
            amount0Desired: amountToMint,
            amount1Desired: amountToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        // Note that the pool defined and fee tier 0.3% must already be created and initialized in order to mint
        (tokenId, liquidity, amount0, amount1) = nonFungiblePositionManager.mint(params);

        // Create a deposit
        _createDeposit(msg.sender, tokenId);

        // Remove allowance and refund in both assets.
        if (amount0 < amountToMint) {
            TransferHelper.safeApprove(_token0, address(nonFungiblePositionManager), 0);
            uint256 refund0 = amountToMint - amount0;
            TransferHelper.safeTransfer(_token0, msg.sender, refund0);
        }

        if (amount1 < amountToMint) {
            TransferHelper.safeApprove(WETH9, address(nonFungiblePositionManager), 0);
            uint256 refund1 = amountToMint - amount1;
            TransferHelper.safeTransfer(WETH9, msg.sender, refund1);
        }
    }

    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        // get position information
        _createDeposit(operator, tokenId);
        return this.onERC721Received.selector;
    }

    function _createDeposit(address owner, uint256 tokenId) internal {
        (
            ,
            ,
            address token0,
            address token1,
            ,
            ,
            ,
            uint128 liquidity,
            ,
            ,
            ,

        ) = nonFungiblePositionManager.positions(tokenId);

        // set the owner and data for position
        // operator is msg.sender
        deposits[tokenId] = Deposit({
            owner: owner,
            liquidity: liquidity,
            token0: token0,
            token1: token1
        });
    }
}
