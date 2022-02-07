pragma solidity 0.8.7;

import "hardhat/console.sol";

/// WARNING: do not use in production ///

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "./interfaces/INonfungiblePositionManager.sol";
import "./Utils.sol";

contract UniswapPoolCreator is Utils, IERC721Receiver {
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
    INonfungiblePositionManager public nonfungiblePositionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address public constant WETH9 = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619; // Intermediate token address.
    uint24 public constant POOL_FEE = 3000;

    // For this example, we will provide equal amounts of liquidity in both assets.
    // Providing liquidity in both assets means liquidity will be earning fees and is considered in-range.
    uint256 public amount0ToMint = 1000;
    uint256 public amount1ToMint = 1000;

    function sqrt(uint256 x) public pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function createPoolAndMintPosition(address _token0) external {
        emit log_named_address("contract add", address(this));
        uint160 srqt_ = 1e27;

        emit log_named_uint("sqrt", srqt_);
        emit log_named_uint("bal0", IERC20(_token0).balanceOf(address(this)));
        emit log_named_uint("bal1", IERC20(WETH9).balanceOf(address(this)));

        address pool = nonfungiblePositionManager.createAndInitializePoolIfNecessary(
            _token0,
            WETH9,
            POOL_FEE,
            srqt_
        );

        emit log_named_address("pool", pool);
        emit log("done");

        mintNewPosition(_token0);
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
        TransferHelper.safeApprove(_token0, address(nonfungiblePositionManager), amount0ToMint);
        TransferHelper.safeApprove(WETH9, address(nonfungiblePositionManager), amount1ToMint);

        emit log("approved");

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
        .MintParams({
            token0: _token0,
            token1: WETH9,
            fee: POOL_FEE,
            tickLower: MIN_TICK,
            tickUpper: MAX_TICK,
            amount0Desired: amount0ToMint,
            amount1Desired: amount1ToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        emit log("params made");

        // Note that the pool defined and fee tier 0.3% must already be created and initialized in order to mint
        // TODO: fix this call
        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);

        // Create a deposit
        _createDeposit(msg.sender, tokenId);

        // Remove allowance and refund in both assets.
        if (amount0 < amount0ToMint) {
            TransferHelper.safeApprove(_token0, address(nonfungiblePositionManager), 0);
            uint256 refund0 = amount0ToMint - amount0;
            TransferHelper.safeTransfer(_token0, msg.sender, refund0);
        }

        if (amount1 < amount1ToMint) {
            TransferHelper.safeApprove(WETH9, address(nonfungiblePositionManager), 0);
            uint256 refund1 = amount1ToMint - amount1;
            TransferHelper.safeTransfer(WETH9, msg.sender, refund1);
        }
    }

    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        emit log("called");
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

        ) = nonfungiblePositionManager.positions(tokenId);

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
