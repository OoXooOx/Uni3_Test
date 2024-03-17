// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {Test, stdError} from "forge-std/Test.sol";
import "./ERC20Mintable.sol";
import "./TestUtils.sol";
import "forge-std/console2.sol";
import "forge-std/console.sol";
import "../src/lib/LiquidityMath.sol";
import "../src/UniswapV3Factory.sol";
import "../src/UniswapV3Manager.sol";


contract myTest is Test, TestUtils {
    
    ERC20Mintable token0;
    ERC20Mintable token1;
    ERC20Mintable uni;
    UniswapV3Factory factory;
    UniswapV3Pool pool;
    UniswapV3Manager manager;

    bool transferInMintCallback = true;
    bool transferInSwapCallback = true;
    bytes extra;

    function setUp() public {
        token1 = new ERC20Mintable("USDC", "USDC", 18);
        token0 = new ERC20Mintable("Ether", "ETH", 18);
        uni = new ERC20Mintable("Uniswap Coin", "UNI", 18);
        factory = new UniswapV3Factory();
        manager = new UniswapV3Manager(address(factory));

        extra = encodeExtra(address(token0), address(token1), address(this));
    }

    

    function testSwapSellEth() public {
        (
            IUniswapV3Manager.MintParams[] memory mints,
            uint256 poolBalance0,
            uint256 poolBalance1
        ) = setupPool(
                PoolParams({
                    wethBalance: 1 ether,
                    usdcBalance: 5000 ether,
                    currentPrice: 5000,
                    mints: mintParamsStructAsArgument(
                        mintParams4args(4545, 5500, 1 ether, 5000 ether)
                    ),
                    transferInMintCallback: true,
                    transferInSwapCallback: true,
                    mintLiquidity: true
                })
            );
        console2.log("poolBalance0", poolBalance0);
        console2.log("poolBalance1", poolBalance1);


        // (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();
        // console2.log("sqrtPriceX96 before swap", sqrtPriceX96);
        // console2.log("tick before swap", uint24(tick));

        // (int24 tickNext, bool initialized) = pool.getNextTick_(1, 84222); // getNextTick_(int24 tickSpacing, int24 tick)
        // uint160 sqrtPriceNextX96 = pool.getSqrtRatioAtTick_(1, 84222); // 60 - tickSpacing
        // console2.log("sqrtPriceNextX96", sqrtPriceNextX96);
        // console2.logInt( tickNext);
        // console2.log("initialized", initialized);
        // uint160 sqrtPriceX96_slot0 = 5341283623238412454227108479223;

        // uint amountOut = pool.getAmountOut_(sqrtPriceX96_slot0, 1, 84222); //  1 60 - tickSpacing
        // console2.log("amountOut", amountOut); //983.834684645847894642  983.835061952220635675
        
        // uint amountIn = pool.getAmountIn_(sqrtPriceX96_slot0, 1, 84222); // 1 60 - tickSpacing
        // console2.log("amountIn", amountIn); //0.198587345020988173
        // ( , , int128 liquidityNet, , ) = pool.ticks(84222);
        // console2.logInt( liquidityNet);  //1517818840967415409418

        // // 1st int24 tick = 85176 sqrtPriceX96_slot0 = 5602277097478613991869082763264 amountIn = 0.198587345020988173 amountOut = 983.834684645847894642
        // // 2nd int24 tick = 84991 sqrtPriceX96_slot0 = 5550922210993867410721910935594 amountIn = 0.279064728044594682 amountOut = 1352.438021290464917189
        // // 3rd int24 tick = 84735 sqrtPriceX96_slot0 = 5480326711419638991903479063784 amountIn = 0.282659534509107639 amountOut = 1335.237989633187055542 
        // // 4th int24 tick = 84479 sqrtPriceX96_slot0 = 5410629031049265453194282770063 amountIn = 0.286300647913260919 amountOut = 1318.256704479892478789 
        // // 5th int24 tick = 84223 sqrtPriceX96_slot0 = 5341817751600736295472531190071 amountIn = 0.002251181215670326 amountOut = 10.232599950607653833
        // // 6th int24 tick = 84222 sqrtPriceX96_slot0 = 5341283623238412454227108479223 amountIn = 0                    amountOut = 0
        // //                                                                                        1.048863436703621739             4999999999999999999995
        // // this means, that for  1.048 of user ETH(token0) we can give to him from pool ~5000USDC(token1), average price of this purchase will be 4770

        // // console.log("XXX", pool.XXX());
        // // console2.log("lower tick", pool.tickBitmap(328)); 

        // // pool.flipTick_(84240); // 1404 
        // // pool.flipTick_(86100); // 1435 
        // console2.logInt( manager.lowerTick());
        // console2.logInt( manager.upperTick());
        // console2.log("lower tick", pool.tickBitmap(328)); 
        // console2.logInt(pool.tickSpacing()); 





        uint256 swapAmount = 2 ether; // 5184247639038531930810
        token0.mint(address(this), swapAmount);
        token0.approve(address(manager), swapAmount);

        (uint256 userBalance0Before, uint256 userBalance1Before) = (
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        );
        console2.log("userBalance0Before", userBalance0Before);
        console2.log("userBalance1Before", userBalance1Before);
       
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();
        console2.log("sqrtPriceX96 before swap", sqrtPriceX96);
        // console2.log("tick before swap", uint24(tick));
        
        console2.log("pool.liquidity before swap", pool.liquidity());
        uint256 amountOut = manager.swapSingle(
            IUniswapV3Manager.SwapSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                fee: 0,
                amountIn: swapAmount,
                sqrtPriceLimitX96: 0 // 4295128739 79228162514264337593543950336    1461446703485210103287273052203988822378723970342
                                                                                            //5604517560314620920028628779008
            })
        );
        (uint160 sqrtPriceX96_, int24 tick_, , , , , ) = pool.slot0();
        console2.log("sqrtPriceX96 after swap", sqrtPriceX96_);
        console2.log("tick after swap");
        console.logInt(tick_);
        /// ↑↑↑↑↑
        // uint256 expectedAmountOut = 0.008371593947078467 ether;
        console2.log("amountOut", amountOut);
        // console2.log("pool.liquidity after swap", pool.liquidity()); // 1517818840967415409418 if we not drain all reserves
        console2.log("pool reserve token1 after swap", subtract(poolBalance1,amountOut));
        (uint256 userBalance0After, uint256 userBalance1After) = (
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        );
        console2.log("userBalance0After", userBalance0After);
        console2.log("userBalance1After", userBalance1After);
        console2.log("pool.liquidity after swap", pool.liquidity());
        console2.log(pool.iterations1());
        console2.log(pool.iterations2());
        console2.log(pool.iterations3());

        // uint256 amountOut1 = manager.swapSingle(
        //     IUniswapV3Manager.SwapSingleParams({
        //         tokenIn: address(token1),
        //         tokenOut: address(token0),
        //         fee: 3000,
        //         amountIn: 2000000 ether,
        //         sqrtPriceLimitX96: sqrtP(60000000) // 4295128739 79228162514264337593543950336    1461446703485210103287273052203988822378723970342
        //                                                                                     //5604517560314620920028628779008
        //     })
        // );



        // (uint160 sqrtPriceX96__, , , , , , ) = pool.slot0();
        // console2.log("sqrtPriceX96 after swap", sqrtPriceX96__);
        // // console2.log("tick after swap", uint24(tick_));
        // // uint256 expectedAmountOut = 0.008371593947078467 ether;
        // console2.log("amountOut", amountOut1);
        // // console2.log("pool.liquidity after swap", pool.liquidity()); // 1546311247949719370887
        // console2.log("pool reserve token0 after swap",   subtract(subtract(poolBalance0,amountOut), amountOut1));
        // (uint256 userBalance0After1, uint256 userBalance1After1) = (
        //     token0.balanceOf(address(this)),
        //     token1.balanceOf(address(this))
        // );
        // console2.log("userBalance0After", userBalance0After1);
        // console2.log("userBalance1After", userBalance1After1);





        // assertEq(amountOut, expectedAmountOut, "invalid ETH out");

        // assertMany(
        //     ExpectedMany({
        //         pool: pool,
        //         tokens: [token0, token1],
        //         liquidity: liquidity(mints[0], 5000),
        //         sqrtPriceX96: 5604422590555458105735383351329, // 5003.830413717752
        //         tick: 85183,
        //         fees: [
        //             uint256(0),
        //             27727650748765949686643356806934465 // 0.000081484242041869
        //         ],
        //         userBalances: [
        //             userBalance0Before + amountOut,
        //             userBalance1Before - swapAmount
        //         ],
        //         poolBalances: [
        //             poolBalance0 - amountOut,
        //             poolBalance1 + swapAmount
        //         ],
        //         position: ExpectedPositionShort({
        //             owner: address(this),
        //             ticks: [mints[0].lowerTick, mints[0].upperTick],
        //             liquidity: liquidity(mints[0], 5000),
        //             feeGrowth: [uint256(0), 0],
        //             tokensOwed: [uint128(0), 0]
        //         }),
        //         ticks: mintParamsToTicks(mints[0], 5000),
        //         observation: ExpectedObservationShort({
        //             index: 0,
        //             timestamp: 1,
        //             tickCumulative: 0,
        //             initialized: true
        //         })
        //     })
        // );
    }

    function subtract(uint x, uint y) public pure returns(uint z) {
        z = x-y;
    }

    ////////////////////////////////////////////////////////////////////////////
    //
    // INTERNAL
    //
    ////////////////////////////////////////////////////////////////////////////
    struct PoolParams {
        uint256 wethBalance;
        uint256 usdcBalance;
        uint256 currentPrice;
        IUniswapV3Manager.MintParams[] mints;
        bool transferInMintCallback;
        bool transferInSwapCallback;
        bool mintLiquidity;
    }

    // struct MintParams {
    //     address tokenA;
    //     address tokenB;
    //     uint24 fee;
    //     int24 lowerTick;
    //     int24 upperTick;
    //     uint256 amount0Desired;
    //     uint256 amount1Desired;
    //     uint256 amount0Min;
    //     uint256 amount1Min;
    // }

     function mintParams4args( uint256 lowerPrice, uint256 upperPrice, uint256 amount0, uint256 amount1) internal view returns (IUniswapV3Manager.MintParams memory params) {
        params = mintParams6args(
            token0,
            token1,
            lowerPrice,
            upperPrice,
            amount0,
            amount1
        );
    }

     function mintParams6args(
        ERC20Mintable token_0,
        ERC20Mintable token_1,
        uint256 lowerPrice,
        uint256 upperPrice,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (IUniswapV3Manager.MintParams memory params) {
        params = mintParamsFromTestUtils(
            address(token_0),
            address(token_1),
            lowerPrice,
            upperPrice,
            amount0,
            amount1
        );
    }

    function mintParamsStructAsArgument(IUniswapV3Manager.MintParams memory mint) internal pure returns (IUniswapV3Manager.MintParams[] memory mints) {
        mints = new IUniswapV3Manager.MintParams[](1);
        mints[0] = mint;
    }

   

    function mintParamsToTicks(
        IUniswapV3Manager.MintParams memory mint,
        uint256 currentPrice
    ) internal pure returns (ExpectedTickShort[2] memory ticks) {
        uint128 liq = liquidity(mint, currentPrice);

        ticks[0] = ExpectedTickShort({
            tick: mint.lowerTick,
            initialized: true,
            liquidityGross: liq,
            liquidityNet: int128(liq)
        });
        ticks[1] = ExpectedTickShort({
            tick: mint.upperTick,
            initialized: true,
            liquidityGross: liq,
            liquidityNet: -int128(liq)
        });
    }

    function liquidity(
        IUniswapV3Manager.MintParams memory params,
        uint256 currentPrice
    ) internal pure returns (uint128 liquidity_) {
        liquidity_ = LiquidityMath.getLiquidityForAmounts(
            sqrtP(currentPrice),
            sqrtP60FromTick(params.lowerTick),
            sqrtP60FromTick(params.upperTick),
            params.amount0Desired,
            params.amount1Desired
        );
    }

     struct PoolParamsFull {
        ERC20Mintable token0;
        ERC20Mintable token1;
        uint256 token0Balance;
        uint256 token1Balance;
        uint256 currentPrice;
        IUniswapV3Manager.MintParams[] mints;
        bool transferInMintCallback;
        bool transferInSwapCallback;
        bool mintLiquidity;
    }

    function setupPool(PoolParams memory params) internal  returns (IUniswapV3Manager.MintParams[] memory mints_, uint256 poolBalance0, uint256 poolBalance1) {
        (pool, mints_, poolBalance0, poolBalance1) = setupPoolFullParams(
            PoolParamsFull({
                token0: token0,
                token1: token1,
                token0Balance: params.wethBalance,
                token1Balance: params.usdcBalance,
                currentPrice: params.currentPrice,
                mints: params.mints,
                transferInMintCallback: params.transferInMintCallback,
                transferInSwapCallback: params.transferInSwapCallback,
                mintLiquidity: params.mintLiquidity
            })
        );
    }

    function setupPoolFullParams(PoolParamsFull memory params) internal  returns (UniswapV3Pool pool_, IUniswapV3Manager.MintParams[] memory mints_, uint256 poolBalance0, uint256 poolBalance1) {
        params.token0.mint(address(this), params.token0Balance+300000);
        params.token1.mint(address(this), params.token1Balance);

        pool_ = deployPool(
            factory,
            address(params.token0),
            address(params.token1),
            0,
            params.currentPrice
        );

        if (params.mintLiquidity) {
            params.token0.approve(address(manager), params.token0Balance);
            params.token1.approve(address(manager), params.token1Balance);

            uint256 poolBalance0Tmp;
            uint256 poolBalance1Tmp;
            for (uint256 i = 0; i < params.mints.length; i++) {
                (poolBalance0Tmp, poolBalance1Tmp) = manager.mint(
                    params.mints[i]
                );
                poolBalance0 += poolBalance0Tmp;
                poolBalance1 += poolBalance1Tmp;
            }
        }

        transferInMintCallback = params.transferInMintCallback;
        transferInSwapCallback = params.transferInSwapCallback;
        mints_ = params.mints;
    }


    // function testForDebug() public {
    //     uint x = 10;
    //     uint y = x+5;
        
    // }
}
