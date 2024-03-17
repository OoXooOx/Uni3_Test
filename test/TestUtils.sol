// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "abdk-math/ABDKMath64x64.sol";

import "../src/interfaces/IUniswapV3Pool.sol";
import "../src/interfaces/IUniswapV3Manager.sol";
import "../src/lib/FixedPoint96.sol";
import "../src/UniswapV3Factory.sol";
import "../src/UniswapV3Pool.sol";

import "./ERC20Mintable.sol";
import "./Assertions.sol";

abstract contract TestUtils is Test
    , Assertions
 {
    mapping(uint24 => uint24) internal tickSpacings;

    constructor() {
        tickSpacings[500] = 10;
        tickSpacings[0] = 200;
    }

    function divRound(int128 x, int128 y)
        internal
        pure
        returns (int128 result)
    {
        int128 quot = ABDKMath64x64.div(x, y);
        result = quot >> 64;

        // Check if remainder is greater than 0.5
        if (quot % 2**64 >= 0x8000000000000000) {
            result += 1;
        }
    }

    // Implements: https://github.com/Uniswap/v3-sdk/blob/b6cd73a71f8f8ec6c40c130564d3aff12c38e693/src/utils/nearestUsableTick.ts
    function nearestUsableTick(int24 tick_, uint24 tickSpacing)
        internal
        pure
        returns (int24 result)
    {
        result =
            int24(divRound(int128(tick_), int128(int24(tickSpacing)))) *
            int24(tickSpacing);

        if (result < TickMath.MIN_TICK) {
            result += int24(tickSpacing);
        } else if (result > TickMath.MAX_TICK) {
            result -= int24(tickSpacing);
        }
    }

    function sqrtP(uint256 price) internal pure returns (uint160) {
        return
            uint160(
                int160(
                    ABDKMath64x64.sqrt(int128(int256(price << 64))) <<
                        (FixedPoint96.RESOLUTION - 64)
                )
            );
    }

    // Calculates sqrtP from price with tick spacing equal to 60;
    function sqrtP60(uint256 price) internal pure returns (uint160) {
        return TickMath.getSqrtRatioAtTick(tick60(price));
    }

    function sqrtP200(uint256 price) internal pure returns (uint160) {
        return TickMath.getSqrtRatioAtTick(tick200(price));
    }

    // Calculates sqrtP from tick with tick spacing equal to 60;
    function sqrtP60FromTick(int24 tick_) internal pure returns (uint160) {
        return TickMath.getSqrtRatioAtTick(nearestUsableTick(tick_, 60));
    }

    function sqrtP200FromTick(int24 tick_) internal pure returns (uint160) {
        return TickMath.getSqrtRatioAtTick(nearestUsableTick(tick_, 200));
    }

    function tick(uint256 price) internal pure returns (int24 tick_) {
        tick_ = TickMath.getTickAtSqrtRatio(sqrtP(price));
    }

    // Calculates tick from price with tick spacing equal to 60;
    function tick60(uint256 price) internal pure returns (int24 tick_) {
        tick_ = tick(price);
        tick_ = nearestUsableTick(tick_, 60);
    }

    function tick200(uint256 price) internal pure returns (int24 tick_) {
        tick_ = tick(price);
        tick_ = nearestUsableTick(tick_, 200);
    }

     function tick5(uint256 price) internal pure returns (int24 tick_) {
        tick_ = tick(price);
        tick_ = nearestUsableTick(tick_, 5);
    }

    function sqrtPToNearestTick(uint160 sqrtP_, uint24 tickSpacing)
        internal
        pure
        returns (int24 tick_)
    {
        tick_ = TickMath.getTickAtSqrtRatio(sqrtP_);
        tick_ = nearestUsableTick(tick_, tickSpacing);
    }

    function encodeError(string memory error)
        internal
        pure
        returns (bytes memory encoded)
    {
        encoded = abi.encodeWithSignature(error);
    }

    function encodeSlippageCheckFailed(uint256 amount0, uint256 amount1)
        internal
        pure
        returns (bytes memory encoded)
    {
        encoded = abi.encodeWithSignature(
            "SlippageCheckFailed(uint256,uint256)",
            amount0,
            amount1
        );
    }

    function encodeExtra(
        address token0_,
        address token1_,
        address payer
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                IUniswapV3Pool.CallbackData({
                    token0: token0_,
                    token1: token1_,
                    payer: payer
                })
            );
    }

    function mintParamsFromTestUtils(
        address tokenA,
        address tokenB,
        uint256 lowerPrice,
        uint256 upperPrice,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (IUniswapV3Manager.MintParams memory params) {
        params = IUniswapV3Manager.MintParams({
            tokenA: tokenA,
            tokenB: tokenB,
            fee: 0,
            lowerTick: tick200(lowerPrice), /// -887200
            upperTick: tick200(upperPrice), /// -887000
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0
        });
    }

    function mintParamsN1(
        address tokenA,
        address tokenB,
        uint256 lowerPrice,
        uint256 upperPrice,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (IUniswapV3Manager.MintParams memory params) {
        params = IUniswapV3Manager.MintParams({
            tokenA: tokenA,
            tokenB: tokenB,
            fee: 0,
            lowerTick: -887200, /// -887200
            upperTick: -887000, /// -887000
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0
        });
    }

    function mintParams(
        address tokenA,
        address tokenB,
        uint160 lowerSqrtP,
        uint160 upperSqrtP,
        uint256 amount0,
        uint256 amount1,
        uint24 fee
    ) internal view returns (IUniswapV3Manager.MintParams memory params) {
        params = IUniswapV3Manager.MintParams({
            tokenA: tokenA,
            tokenB: tokenB,
            fee: fee,
            lowerTick: sqrtPToNearestTick(lowerSqrtP, tickSpacings[fee]),
            upperTick: sqrtPToNearestTick(upperSqrtP, tickSpacings[fee]),
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0
        });
    }

    function deployPool(
        UniswapV3Factory factory,
        address token0,
        address token1,
        uint24 fee,
        uint256 currentPrice
    ) internal returns (UniswapV3Pool pool) {
        pool = UniswapV3Pool(factory.createPool(token0, token1, fee));
        pool.initialize(sqrtP(currentPrice));
    }
}
