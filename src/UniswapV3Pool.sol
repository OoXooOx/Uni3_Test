// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "prb-math/PRBMath.sol";
import "./NoDelegateCall.sol";
import './lib/SafeCast.sol';
import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV3FlashCallback.sol";
import "./interfaces/IUniswapV3MintCallback.sol";
import "./interfaces/IUniswapV3Pool.sol";
import "./interfaces/IUniswapV3PoolDeployer.sol";
import "./interfaces/IUniswapV3SwapCallback.sol";
import './lib/TransferHelper.sol';
import "./lib/FixedPoint128.sol";
import "./lib/LiquidityMath.sol";
import "./lib/Math.sol";
import "./lib/Oracle.sol";
import "./lib/Position.sol";
import "./lib/SwapMath.sol";
import "./lib/Tick.sol";
import "./lib/TickBitmap.sol";
import "./lib/TickMath.sol";

contract UniswapV3Pool is IUniswapV3Pool, NoDelegateCall {
    using Oracle for Oracle.Observation[65535];
    using Position for Position.Info;
    using Position for mapping(bytes32 => Position.Info);
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using SafeCast for uint256;
    using SafeCast for int256;

    struct ProtocolFees {
        uint128 token0;
        uint128 token1;
    }

    ProtocolFees public protocolFees;

    

    error AlreadyInitialized();
    error FlashLoanNotPaid();
    error InsufficientInputAmount();
    error InvalidPriceLimit();
    error InvalidTickRange();
    error NotEnoughLiquidity();
    error ZeroLiquidity();

    event Burn(
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    event Collect(
        address indexed owner,
        address recipient,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint256 amount0,
        uint256 amount1
    );

    event Flash(address indexed recipient, uint256 amount0, uint256 amount1);

    event IncreaseObservationCardinalityNext(
        uint16 observationCardinalityNextOld,
        uint16 observationCardinalityNextNew
    );

    event Mint(
        address sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    // Pool parameters
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    int24 public immutable tickSpacing;
    uint24 public immutable fee;

    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;

    // First slot will contain essential data
    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        uint16 observationCardinality;
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol;
        // whether the pool is locked
        bool unlocked;
    }
    // inheritdoc IUniswapV3PoolState
    Slot0 public slot0;


    struct SwapState {
        // the amount remaining to be swapped in/out of the input/output asset
        int256 amountSpecifiedRemaining;
        // the amount already swapped out/in of the output/input asset
        int256 amountCalculated;
        // current sqrt(price)
        uint160 sqrtPriceX96;
        // the tick associated with the current price
        int24 tick;
        // the global fee growth of the input token
        uint256 feeGrowthGlobalX128;
        // amount of input token paid as protocol fee
        uint128 protocolFee;
        // the current liquidity in range
        uint128 liquidity;
    }

    struct StepState {
        uint160 sqrtPriceStartX96;
        int24 nextTick;
        bool initialized;
        uint160 sqrtPriceNextX96;
        uint256 amountIn;
        uint256 amountOut;
        uint256 feeAmount;
    }

    
    modifier lock() {
        require(slot0.unlocked, 'LOK');
        slot0.unlocked = false;
        _;
        slot0.unlocked = true;
    }

    // Amount of liquidity, L.
    uint128 public liquidity;

    mapping(int24 => Tick.Info) public ticks;
    mapping(int16 => uint256) public tickBitmap;
    mapping(bytes32 => Position.Info) public positions;
    Oracle.Observation[65535] public observations;

    constructor() {
        int24 _tickSpacing;
        (factory, token0, token1, tickSpacing, fee) = IUniswapV3PoolDeployer(msg.sender).parameters();
        

    }


    function initialize(uint160 sqrtPriceX96) public {
        if (slot0.sqrtPriceX96 != 0) revert AlreadyInitialized();

        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        (uint16 cardinality, uint16 cardinalityNext) = observations.initialize(
            _blockTimestamp()
        );

        slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex: 0,
            observationCardinality: cardinality,
            observationCardinalityNext: cardinalityNext,
            feeProtocol: 0,
            unlocked: true
        });
    }

    struct ModifyPositionParams {
        address owner;
        int24 lowerTick;
        int24 upperTick;
        int128 liquidityDelta;
    }

    bool public XXX;
    function _modifyPosition(ModifyPositionParams memory params)
        internal
        returns (
            Position.Info storage position,
            int256 amount0,
            int256 amount1
        )
    {
        // gas optimizations
        Slot0 memory slot0_ = slot0;
        uint256 feeGrowthGlobal0X128_ = feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128_ = feeGrowthGlobal1X128;

        position = positions.get(
            params.owner,
            params.lowerTick,
            params.upperTick
        );

        bool flippedLower = ticks.update(
            params.lowerTick,
            slot0_.tick,
            int128(params.liquidityDelta),
            feeGrowthGlobal0X128_,
            feeGrowthGlobal1X128_,
            false
        );
        XXX=flippedLower;
        bool flippedUpper = ticks.update(
            params.upperTick,
            slot0_.tick,
            int128(params.liquidityDelta),
            feeGrowthGlobal0X128_,
            feeGrowthGlobal1X128_,
            true
        );

        if (flippedLower) {
            tickBitmap.flipTick(params.lowerTick, tickSpacing);
        }

        if (flippedUpper) {
            tickBitmap.flipTick(params.upperTick, tickSpacing);
        }

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = ticks
            .getFeeGrowthInside(
                params.lowerTick,
                params.upperTick,
                slot0_.tick,
                feeGrowthGlobal0X128_,
                feeGrowthGlobal1X128_
            );

        position.update(
            params.liquidityDelta,
            feeGrowthInside0X128,
            feeGrowthInside1X128
        );

        if (slot0_.tick < params.lowerTick) {
            amount0 = Math.calcAmount0Delta(
                TickMath.getSqrtRatioAtTick(params.lowerTick),
                TickMath.getSqrtRatioAtTick(params.upperTick),
                params.liquidityDelta
            );
        } else if (slot0_.tick < params.upperTick) {
            amount0 = Math.calcAmount0Delta(
                slot0_.sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(params.upperTick),
                params.liquidityDelta
            );

            amount1 = Math.calcAmount1Delta(
                TickMath.getSqrtRatioAtTick(params.lowerTick),
                slot0_.sqrtPriceX96,
                params.liquidityDelta
            );

            liquidity = LiquidityMath.addLiquidity(
                liquidity,
                params.liquidityDelta
            );
        } else {
            amount1 = Math.calcAmount1Delta(
                TickMath.getSqrtRatioAtTick(params.lowerTick),
                TickMath.getSqrtRatioAtTick(params.upperTick),
                params.liquidityDelta
            );
        }
    }

    function mint(
        address owner,
        int24 lowerTick,
        int24 upperTick,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1) {
        if (
            lowerTick >= upperTick ||
            lowerTick < TickMath.MIN_TICK ||
            upperTick > TickMath.MAX_TICK
        ) revert InvalidTickRange();

        if (amount == 0) revert ZeroLiquidity();

        (, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: owner,
                lowerTick: lowerTick,
                upperTick: upperTick,
                liquidityDelta: int128(amount)
            })
        );

        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        uint256 balance0Before;
        uint256 balance1Before;

        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();

        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(
            amount0,
            amount1,
            data
        );

        if (amount0 > 0 && balance0Before + amount0 > balance0())
            revert InsufficientInputAmount();

        if (amount1 > 0 && balance1Before + amount1 > balance1())
            revert InsufficientInputAmount();

        emit Mint(
            msg.sender,
            owner,
            lowerTick,
            upperTick,
            amount,
            amount0,
            amount1
        );
    }

    function burn(
        int24 lowerTick,
        int24 upperTick,
        uint128 amount
    ) public returns (uint256 amount0, uint256 amount1) {
        (
            Position.Info storage position,
            int256 amount0Int,
            int256 amount1Int
        ) = _modifyPosition(
                ModifyPositionParams({
                    owner: msg.sender,
                    lowerTick: lowerTick,
                    upperTick: upperTick,
                    liquidityDelta: -(int128(amount))
                })
            );

        amount0 = uint256(-amount0Int);
        amount1 = uint256(-amount1Int);

        if (amount0 > 0 || amount1 > 0) {
            (position.tokensOwed0, position.tokensOwed1) = (
                position.tokensOwed0 + uint128(amount0),
                position.tokensOwed1 + uint128(amount1)
            );
        }

        emit Burn(msg.sender, lowerTick, upperTick, amount, amount0, amount1);
    }

    function collect(
        address recipient,
        int24 lowerTick,
        int24 upperTick,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) public returns (uint128 amount0, uint128 amount1) {
        Position.Info storage position = positions.get(
            msg.sender,
            lowerTick,
            upperTick
        );

        amount0 = amount0Requested > position.tokensOwed0
            ? position.tokensOwed0
            : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1
            ? position.tokensOwed1
            : amount1Requested;

        if (amount0 > 0) {
            position.tokensOwed0 -= amount0;
            IERC20(token0).transfer(recipient, amount0);
        }

        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
            IERC20(token1).transfer(recipient, amount1);
        }

        emit Collect(
            msg.sender,
            recipient,
            lowerTick,
            upperTick,
            amount0,
            amount1
        );
    }

    // function swap(
    //     address recipient,
    //     bool zeroForOne,
    //     uint256 amountSpecified, //300 000
    //     uint160 sqrtPriceLimitX96,
    //     bytes calldata data
    // ) public returns (int256 amount0, int256 amount1) {
    //     // Caching for gas saving
    //     Slot0 memory slot0_ = slot0;
    //     uint128 liquidity_ = liquidity;

    //     if (
    //         zeroForOne
    //             ? sqrtPriceLimitX96 > slot0_.sqrtPriceX96 ||
    //                 sqrtPriceLimitX96 < TickMath.MIN_SQRT_RATIO
    //             : sqrtPriceLimitX96 < slot0_.sqrtPriceX96 ||
    //                 sqrtPriceLimitX96 > TickMath.MAX_SQRT_RATIO
    //     ) revert InvalidPriceLimit();

    //     SwapState memory state = SwapState({
    //         amountSpecifiedRemaining: amountSpecified, //300 000
    //         amountCalculated: 0,
    //         sqrtPriceX96: slot0_.sqrtPriceX96,
    //         tick: slot0_.tick,
    //         feeGrowthGlobalX128: zeroForOne
    //             ? feeGrowthGlobal0X128
    //             : feeGrowthGlobal1X128,
    //         liquidity: liquidity_
    //     });

    //     while (
    //         state.amountSpecifiedRemaining > 0 && // 300 000
    //         state.sqrtPriceX96 != sqrtPriceLimitX96
    //     ) {
    //         StepState memory step;

    //         step.sqrtPriceStartX96 = state.sqrtPriceX96;

    //         (step.nextTick, ) = tickBitmap.nextInitializedTickWithinOneWord(
    //             state.tick,
    //             int24(tickSpacing),
    //             zeroForOne
    //         );

    //         step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.nextTick);

    //         (
    //             state.sqrtPriceX96,
    //             step.amountIn,
    //             step.amountOut,
    //             step.feeAmount
    //         ) = SwapMath.computeSwapStep(
    //             state.sqrtPriceX96,
    //             (
    //                 zeroForOne // false (User sell token1)  Price go upper
    //                     ? step.sqrtPriceNextX96 < sqrtPriceLimitX96
    //                     : step.sqrtPriceNextX96 > sqrtPriceLimitX96
    //             )
    //                 ? sqrtPriceLimitX96
    //                 : step.sqrtPriceNextX96,
    //             state.liquidity,
    //             state.amountSpecifiedRemaining, // 300 000
    //             fee
    //         );

    //         //     function computeSwapStep(
    //         //     uint160 sqrtPriceCurrentX96,
    //         //     uint160 sqrtPriceTargetX96,
    //         //     uint128 liquidity,
    //         //     uint256 amountRemaining,
    //         //     uint24 fee
    //         // )
    //         //     internal
    //         //     pure
    //         //     returns (
    //         //         uint160 sqrtPriceNextX96,
    //         //         uint256 amountIn,
    //         //         uint256 amountOut,
    //         //         uint256 feeAmount
    //         //     )
    //         // {
    //         //     bool zeroForOne = sqrtPriceCurrentX96 >= sqrtPriceTargetX96;
    //         //     uint256 amountRemainingLessFee = PRBMath.mulDiv(
    //         //         amountRemaining,
    //         //         1e6 - fee,
    //         //         1e6
    //         //     );

    //         //     amountIn = zeroForOne
    //         //         ? Math.calcAmount0Delta(
    //         //             sqrtPriceCurrentX96,
    //         //             sqrtPriceTargetX96,
    //         //             liquidity,
    //         //             true
    //         //         )
    //         //         : Math.calcAmount1Delta(
    //         //             sqrtPriceCurrentX96,
    //         //             sqrtPriceTargetX96,
    //         //             liquidity,
    //         //             true
    //         //         );

    //         //     if (amountRemainingLessFee >= amountIn)
    //         //         sqrtPriceNextX96 = sqrtPriceTargetX96;
    //         //     else
    //         //         sqrtPriceNextX96 = Math.getNextSqrtPriceFromInput(
    //         //             sqrtPriceCurrentX96,
    //         //             liquidity,
    //         //             amountRemainingLessFee,
    //         //             zeroForOne
    //         //         );

    //         //     bool max = sqrtPriceNextX96 == sqrtPriceTargetX96;

    //         //     if (zeroForOne) {
    //         //         amountIn = max
    //         //             ? amountIn
    //         //             : Math.calcAmount0Delta(
    //         //                 sqrtPriceCurrentX96,
    //         //                 sqrtPriceNextX96,
    //         //                 liquidity,
    //         //                 true
    //         //             );
    //         //         amountOut = Math.calcAmount1Delta(
    //         //             sqrtPriceCurrentX96,
    //         //             sqrtPriceNextX96,
    //         //             liquidity,
    //         //             false
    //         //         );
    //         //     } else {
    //         //         amountIn = max
    //         //             ? amountIn
    //         //             : Math.calcAmount1Delta(
    //         //                 sqrtPriceCurrentX96,
    //         //                 sqrtPriceNextX96,
    //         //                 liquidity,
    //         //                 true
    //         //             );
    //         //         amountOut = Math.calcAmount0Delta(
    //         //             sqrtPriceCurrentX96,
    //         //             sqrtPriceNextX96,
    //         //             liquidity,
    //         //             false
    //         //         );
    //         //     }

    //         //     if (!max) {
    //         //         feeAmount = amountRemaining - amountIn;
    //         //     } else {
    //         //         feeAmount = Math.mulDivRoundingUp(amountIn, fee, 1e6 - fee);
    //         //     }
    //         // }

    //         state.amountSpecifiedRemaining -= step.amountIn + step.feeAmount;
    //         //state.amountSpecifiedRemaining == 5000
    //         state.amountCalculated += step.amountOut;

    //         if (state.liquidity > 0) {
    //             state.feeGrowthGlobalX128 += PRBMath.mulDiv(
    //                 step.feeAmount,
    //                 FixedPoint128.Q128,
    //                 state.liquidity
    //             );
    //         }

    //         if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
    //             int128 liquidityDelta = ticks.cross(
    //                 step.nextTick,
    //                 (
    //                     zeroForOne
    //                         ? state.feeGrowthGlobalX128
    //                         : feeGrowthGlobal0X128
    //                 ),
    //                 (
    //                     zeroForOne
    //                         ? feeGrowthGlobal1X128
    //                         : state.feeGrowthGlobalX128
    //                 )
    //             );

    //             if (zeroForOne) liquidityDelta = -liquidityDelta;

    //             state.liquidity = LiquidityMath.addLiquidity(
    //                 state.liquidity,
    //                 liquidityDelta
    //             );

    //             if (state.liquidity == 0) revert NotEnoughLiquidity();

    //             state.tick = zeroForOne ? step.nextTick - 1 : step.nextTick;
    //         } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
    //             state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
    //         }
    //     }

    //     if (state.tick != slot0_.tick) {
    //         (
    //             uint16 observationIndex,
    //             uint16 observationCardinality
    //         ) = observations.write(
    //                 slot0_.observationIndex,
    //                 _blockTimestamp(),
    //                 slot0_.tick,
    //                 slot0_.observationCardinality,
    //                 slot0_.observationCardinalityNext
    //             );

    //         (
    //             slot0.sqrtPriceX96,
    //             slot0.tick,
    //             slot0.observationIndex,
    //             slot0.observationCardinality
    //         ) = (
    //             state.sqrtPriceX96,
    //             state.tick,
    //             observationIndex,
    //             observationCardinality
    //         );
    //     } else {
    //         slot0.sqrtPriceX96 = state.sqrtPriceX96;
    //     }

    //     if (liquidity_ != state.liquidity) liquidity = state.liquidity;

    //     if (zeroForOne) {
    //         feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
    //     } else {
    //         feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
    //     }

    //     (amount0, amount1) = zeroForOne
    //         ? (
    //             int256(amountSpecified - state.amountSpecifiedRemaining),
    //             -int256(state.amountCalculated)
    //         )
    //         : (
    //             -int256(state.amountCalculated),
    //             int256(amountSpecified - state.amountSpecifiedRemaining)
    //         );

    //     if (zeroForOne) {
    //         IERC20(token1).transfer(recipient, uint256(-amount1));

    //         uint256 balance0Before = balance0();
    //         IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
    //             amount0,
    //             amount1,
    //             data
    //         );
    //         if (balance0Before + uint256(amount0) > balance0())
    //             revert InsufficientInputAmount();
    //     } else {
    //         IERC20(token0).transfer(recipient, uint256(-amount0));

    //         uint256 balance1Before = balance1();
    //         IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
    //             amount0,
    //             amount1,
    //             data
    //         );
    //         if (balance1Before + uint256(amount1) > balance1())
    //             revert InsufficientInputAmount();
    //     }

    //     emit Swap(
    //         msg.sender,
    //         recipient,
    //         amount0,
    //         amount1,
    //         slot0.sqrtPriceX96,
    //         state.liquidity,
    //         slot0.tick
    //     );
    // }

    struct SwapCache {
        // the protocol fee for the input token
        uint8 feeProtocol;
        // liquidity at the beginning of the swap
        uint128 liquidityStart;
        // the timestamp of the current block
        uint32 blockTimestamp;
        // the current value of the tick accumulator, computed only if we cross an initialized tick
        int56 tickCumulative;
        // the current value of seconds per liquidity accumulator, computed only if we cross an initialized tick
        uint160 secondsPerLiquidityCumulativeX128;
        // whether we've computed and cached the above two accumulators
        bool computedLatestObservation;
    }

    struct StepComputations {
        // the price at the beginning of the step
        uint160 sqrtPriceStartX96;
        // the next tick to swap to from the current tick in the swap direction
        int24 tickNext;
        // whether tickNext is initialized or not
        bool initialized;
        // sqrt(price) for the next tick (1/0)
        uint160 sqrtPriceNextX96;
        // how much is being swapped in in this step
        uint256 amountIn;
        // how much is being swapped out
        uint256 amountOut;
        // how much fee is being paid in
        uint256 feeAmount;
    }
    uint public iterations1;
    uint public iterations2;
    uint public iterations3;
     function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external  noDelegateCall returns (int256 amount0, int256 amount1) {
        require(amountSpecified != 0, 'AS');

        Slot0 memory slot0Start = slot0;

        require(slot0Start.unlocked, 'LOK');
        require(
            zeroForOne
                ? sqrtPriceLimitX96 < slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 > slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO,
            'SPL'
        );

        slot0.unlocked = false;

        SwapCache memory cache =
            SwapCache({
                liquidityStart: liquidity,
                blockTimestamp: _blockTimestamp(),
                feeProtocol: zeroForOne ? (slot0Start.feeProtocol % 16) : (slot0Start.feeProtocol >> 4),
                secondsPerLiquidityCumulativeX128: 0,
                tickCumulative: 0,
                computedLatestObservation: false
            });

        bool exactInput = amountSpecified > 0;

        SwapState memory state =
            SwapState({
                amountSpecifiedRemaining: amountSpecified,
                amountCalculated: 0,
                sqrtPriceX96: slot0Start.sqrtPriceX96,
                tick: slot0Start.tick,
                feeGrowthGlobalX128: zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128,
                protocolFee: 0,
                liquidity: cache.liquidityStart
            });

        // continue swapping as long as we haven't used the entire input/output and haven't reached the price limit
        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != sqrtPriceLimitX96) {
            StepComputations memory step;
            iterations1++;
            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (step.tickNext, step.initialized) = tickBitmap.nextInitializedTickWithinOneWord(
                state.tick, // 1st iter 85176     // 2nd iter 84992 // last 84223
                tickSpacing, // 1   60  
                zeroForOne  /// true
            ); 

            // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            // get the price for the next tick  //last step.tickNext = 84222
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);// 5550922210993867410721910935594 // last 5341283623238412454227108479223

            // compute values to swap to the target tick, price limit, or point where input/output amount is exhausted

            //// state.sqrtPriceX96 = 5550922210993867410721910935594   step.amountIn 0.202315215108743053 
             //// last iter  state.sqrtPriceX96 = 5341283623238412454227108479223   step.amountIn 0.002251181215670326
            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,// 1st 5602277097478613991869082763264 //  // last iter  state.sqrtPriceX96 = 5341817751600736295472531190071
                (zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : step.sqrtPriceNextX96 > sqrtPriceLimitX96)
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96, //  1st 5550922210993867410721910935594 // last iter = 5341283623238412454227108479223
                state.liquidity, 
                state.amountSpecifiedRemaining, // 1st  2 // 2nd 2-0.2 // last 2-1.046612255487951413
                fee
            );

            if (exactInput) {
                // tick 85176 - 84992 = 184        85176-84222 = 954  //// last iter 
                state.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount).toInt256(); // 2 - 0.202315215108743053 = 1.8  // last iter 2-1.048863436703621739
                state.amountCalculated -= step.amountOut.toInt256(); // state.amountCalculated is int, so 0 - 983=> state.amountCalculated= -983  //last - 4999999999999999999995
               
            } else {
                state.amountSpecifiedRemaining += step.amountOut.toInt256();
                state.amountCalculated += (step.amountIn + step.feeAmount).toInt256();
            }

            ///

            // if the protocol fee is on, calculate how much is owed, decrement feeAmount, and increment protocolFee
            if (cache.feeProtocol > 0) {
                uint256 delta = step.feeAmount / cache.feeProtocol;
                step.feeAmount -= delta;
                state.protocolFee += uint128(delta);
            }

            // update global fee tracker
            if (state.liquidity > 0)
                state.feeGrowthGlobalX128 += PRBMath.mulDiv(step.feeAmount, FixedPoint128.Q128, state.liquidity);
 
            // shift tick if we reached the next price
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {   // 5550922210993867410721910935594 == 5550922210993867410721910935594  true
                // if the tick is initialized, run the tick transition
                if (step.initialized) { //initialized false // last iter true
                    // check for the placeholder value, which we replace with the actual value the first time the swap
                    // crosses an initialized tick
                    iterations2++;
                    if (!cache.computedLatestObservation) {
                        (cache.tickCumulative, cache.secondsPerLiquidityCumulativeX128) = observations.observeSingle(
                            cache.blockTimestamp,
                            0,
                            slot0Start.tick,
                            slot0Start.observationIndex,
                            cache.liquidityStart,
                            slot0Start.observationCardinality
                        );
                        cache.computedLatestObservation = true;
                    }
                    int128 liquidityNet =
                        ticks.cross(
                            step.tickNext, // last 84222
                            (zeroForOne ? state.feeGrowthGlobalX128 : feeGrowthGlobal0X128),
                            (zeroForOne ? feeGrowthGlobal1X128 : state.feeGrowthGlobalX128)
                        );
                    // if we're moving leftward, we interpret liquidityNet as the opposite sign
                    // safe because liquidityNet cannot be type(int128).min
                    if (zeroForOne) liquidityNet = -liquidityNet; // last -1517818840967415409418 

                    state.liquidity = LiquidityMath.addLiquidity(state.liquidity, liquidityNet); // last state.liquidity = 0
                }

                state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext; // state.tick = step.tickNext             state.tick = step.tickNext - 1   84992-1=84991
                //last iter ↑↑↑↑  state.tick = 842222
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
                iterations3++;
            }
        }    //////////////////////////WHILE END///////////////////////////////////////////////////////////////////////////////////////////

        

        // update tick and write an oracle entry if the tick change 
        if (state.tick != slot0Start.tick) { // true
            (uint16 observationIndex, uint16 observationCardinality) =
                observations.write(
                    slot0Start.observationIndex,
                    cache.blockTimestamp,
                    slot0Start.tick,
                    cache.liquidityStart,
                    slot0Start.observationCardinality,
                    slot0Start.observationCardinalityNext
                );
            (slot0.sqrtPriceX96, slot0.tick, slot0.observationIndex, slot0.observationCardinality) = (
                state.sqrtPriceX96, // slot0.sqrtPriceX96 = 5550922210993867410721910935594
                state.tick,   // we change slot0.tick = state.tick = 84992
                observationIndex,
                observationCardinality
            );
        } else {
            // otherwise just update the price
            slot0.sqrtPriceX96 = state.sqrtPriceX96;
        }

        // update liquidity if it changed
        if (cache.liquidityStart != state.liquidity) liquidity = state.liquidity; // false thus we  have //initialized false and skip liquidity modification

        // update fee growth global and, if necessary, protocol fees
        // overflow is acceptable, protocol has to withdraw before it hits type(uint128).max fees
        if (zeroForOne) {
            feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
            if (state.protocolFee > 0) protocolFees.token0 += state.protocolFee;
        } else {
            feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
            if (state.protocolFee > 0) protocolFees.token1 += state.protocolFee;
        }

        (amount0, amount1) = zeroForOne == exactInput
            ? (amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated)
            : (state.amountCalculated, amountSpecified - state.amountSpecifiedRemaining);

        // do the transfers and collect payment
        if (zeroForOne) {
            if (amount1 < 0) TransferHelper.safeTransfer(token1, recipient, uint256(-amount1));

            uint256 balance0Before = balance0();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
            require(balance0Before+uint256(amount0) <= balance0(), 'IIA');
        } else {
            if (amount0 < 0) TransferHelper.safeTransfer(token0, recipient, uint256(-amount0));

            uint256 balance1Before = balance1();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
            require(balance1Before+uint256(amount1) <= balance1(), 'IIA');
        }

        emit Swap(msg.sender, recipient, amount0, amount1, state.sqrtPriceX96, state.liquidity, state.tick);
        slot0.unlocked = true;
    }


    function flash(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) public {
        uint256 fee0 = Math.mulDivRoundingUp(amount0, fee, 1e6);
        uint256 fee1 = Math.mulDivRoundingUp(amount1, fee, 1e6);

        uint256 balance0Before = IERC20(token0).balanceOf(address(this));
        uint256 balance1Before = IERC20(token1).balanceOf(address(this));

        if (amount0 > 0) IERC20(token0).transfer(msg.sender, amount0);
        if (amount1 > 0) IERC20(token1).transfer(msg.sender, amount1);

        IUniswapV3FlashCallback(msg.sender).uniswapV3FlashCallback(
            fee0,
            fee1,
            data
        );

        if (IERC20(token0).balanceOf(address(this)) < balance0Before + fee0)
            revert FlashLoanNotPaid();
        if (IERC20(token1).balanceOf(address(this)) < balance1Before + fee1)
            revert FlashLoanNotPaid();

        emit Flash(msg.sender, amount0, amount1);
    }

    // function observe(uint32[] calldata secondsAgos)
    //     public
    //     view
    //     returns (int56[] memory tickCumulatives)
    // {
    //     return
    //         observations.observe(
    //             _blockTimestamp(),
    //             secondsAgos,
    //             slot0.tick,
    //             slot0.observationIndex,

    //             slot0.observationCardinality
    //         );
    // }

    function increaseObservationCardinalityNext(
        uint16 observationCardinalityNext
    ) public {
        uint16 observationCardinalityNextOld = slot0.observationCardinalityNext;
        uint16 observationCardinalityNextNew = observations.grow(
            observationCardinalityNextOld,
            observationCardinalityNext
        );

        if (observationCardinalityNextNew != observationCardinalityNextOld) {
            slot0.observationCardinalityNext = observationCardinalityNextNew;
            emit IncreaseObservationCardinalityNext(
                observationCardinalityNextOld,
                observationCardinalityNextNew
            );
        }
    }

    ////////////////////////////////////////////////////////////////////////////
    //
    // INTERNAL
    //
    ////////////////////////////////////////////////////////////////////////////
    function balance0() internal returns (uint256 balance) {
        balance = IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal returns (uint256 balance) {
        balance = IERC20(token1).balanceOf(address(this));
    }

    function _blockTimestamp() internal view returns (uint32 timestamp) {
        timestamp = uint32(block.timestamp);
    }

    function getNextTick_(int24 tickSpacing_, int24 tick) public view returns (int24 tickNext, bool initialized) {
         (tickNext, initialized) = tickBitmap.nextInitializedTickWithinOneWord(
                tick,
                tickSpacing_,
                true
        );
    }

    function getSqrtRatioAtTick_(int24 tickSpacing_, int24 tick) public view returns (uint160 sqrtPriceNextX96) {
        (int24 x, ) = getNextTick_(tickSpacing_,tick);
        sqrtPriceNextX96=TickMath.getSqrtRatioAtTick(x);
    }
    //84992


    function getAmountIn_(uint160 sqrtPriceX96, int24 tickSpacing_, int24 tick) public view returns(uint amountIn) {
        amountIn = Math.calcAmount0Delta(
                sqrtPriceX96,
                getSqrtRatioAtTick_(tickSpacing_,tick),
                liquidity,
                true
            );
    }

    function flipTick_(int24 _tick) public {
        tickBitmap.flipTick(_tick, 1);
    }
    function getAmountOut_(uint160 sqrtPriceX96, int24 tickSpacing_, int24 tick) public view returns(uint amountOut) {
        amountOut =  Math.calcAmount1Delta(
            getSqrtRatioAtTick_(tickSpacing_,tick),
            sqrtPriceX96,
            liquidity, 
            false
        );
    }
}
