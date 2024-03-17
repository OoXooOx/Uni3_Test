// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {Test, stdError} from "forge-std/Test.sol";
import "./ERC20Mintable.sol";
import "./TestUtils.sol";
import "forge-std/console2.sol";
import "forge-std/console.sol";
import "../src/interfaces/IERC20.sol";

interface INonfungiblePositionManager {
        struct MintParams {
            address token0;
            address token1;
            uint24 fee;
            int24 tickLower;
            int24 tickUpper;
            uint256 amount0Desired;
            uint256 amount1Desired;
            uint256 amount0Min;
            uint256 amount1Min;
            address recipient;
            uint256 deadline;
        }

        function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

        struct DecreaseLiquidityParams {
            uint256 tokenId;
            uint128 liquidity;
            uint256 amount0Min;
            uint256 amount1Min;
            uint256 deadline;
        }
    
            function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );


        function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
}

interface IUniswapV3RouterCUTED  {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}


contract testNuar is Test, TestUtils {
    uint _deadline = 1710925528; //////// CHECK THIS 20/03/2024
    struct PositionForRemove {
        uint tokenId;
        uint128 liquidity;
    }
    mapping(uint=>PositionForRemove) positionsForRemove;
    uint counter;

    INonfungiblePositionManager manager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    UniswapV3Pool pool = UniswapV3Pool(0x53A509d1cF1de11B418e82DaC58c0648a0fdaFCA);
    ERC20Mintable token0 = ERC20Mintable(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0);
    ERC20Mintable token1 = ERC20Mintable(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IUniswapV3RouterCUTED router = IUniswapV3RouterCUTED(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    function setUp() public {
       
    }

 

    function addLiquidity1000weiOfToken0() public {
        (uint160 sqrtPriceX96_, int24 tick_, , , , , ) = pool.slot0();
        //--887272
         // mint 1000 token0 for add liquidity. 
        uint amount = 30 ether; 
        deal(address(token0), address(this), amount);
        token0.approve(address(manager), amount);
        // console.logInt(tick_);
        int24 upperTick =  nearestUsableTick(tick_+500, 200); // -275600
        if(upperTick>887200) upperTick=887200;
        if(upperTick<-886000) upperTick=-600000;
        //-886800
        // add 1000 liquidity.
        (
            uint256 tokenId,
            uint128 liquidity_, 
            uint256 poolBalance0_1,
            uint256 poolBalance1_1
              ) = manager.mint( 
                    INonfungiblePositionManager.MintParams({
                        token0: address(token0),
                        token1: address(token1),
                        fee: 10000, 
                        tickLower: nearestUsableTick(upperTick-200, 200),
                        tickUpper:  upperTick, 
                        amount0Desired: amount,
                        amount1Desired: 0,
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: address(this),
                        deadline: _deadline
                })
        );
    }
        

     function testFORKSwapSellEthSunday() public {
        (uint256 userBalance0Before_, uint256 userBalance1Before_) = (
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        );
        // console2.log("userBalance0BeforeMint", userBalance0Before_);
        // console2.log("userBalance1BeforeMint", userBalance1Before_);
        ( , int24 tick_at_the_start, , , , , ) = pool.slot0();
        console2.log("tick_at_the_start");
         console.logInt(tick_at_the_start);

        uint iterations = 3;
        addLiquidity1000weiOfToken0();

        for(uint i; i<iterations; i++){
             work(); 
        }
       
        
        (uint160 sqrtPriceX96_in_the_end, int24 tick_in_the_end, , , , , ) = pool.slot0();
        console2.log("sqrtPriceX96_in_the_end", sqrtPriceX96_in_the_end);
        console2.log("tick_in_the_end");
        console.logInt(tick_in_the_end);
        console.log("liquid", pool.liquidity());

    }

    function work() public {

        uint256 swapAmount = 1 ether; 
        // mint token1 for first swap. We move price to boundary
        deal(address(token1), address(this), swapAmount);
        token1.approve(address(router), swapAmount);
      
        // (uint256 userBalance0Before_, uint256 userBalance1Before_) = (
        //     token0.balanceOf(address(this)),
        //     token1.balanceOf(address(this))
        // );
        // console2.log("userBalance0BeforeMint", userBalance0Before_);
        // console2.log("userBalance1BeforeMint", userBalance1Before_);

        
        //first swap start. We move price to 887271 tick  
        uint256 amountOut = router.exactInputSingle(
                IUniswapV3RouterCUTED.ExactInputSingleParams({
                    tokenIn:address(token1),
                    tokenOut:address(token0),
                    fee:10000,
                    recipient:address(this),
                    deadline: _deadline,
                    amountIn: swapAmount,
                    amountOutMinimum:0,
                    sqrtPriceLimitX96:0
                }) 
            );
        ///////////////////////FIRST SWAP END //////////////////////////////////

        ///////////////////////ADD LIQUIDITY START 100mln //////////////////////////////////
        (uint160 sqrtPriceX96_, int24 tick_, , , , , ) = pool.slot0();
        // // console2.log("sqrtPriceX96 after swap", sqrtPriceX96_);
        // // console2.log("tick after swap");
        // // console.logInt(tick_);
        require(tick_==887271 || tick_==887272, "not 887271/72 tick");
        
        // mint 100mln token1 for add liquidity. 
        deal(address(token1), address(this), 100_000_000 ether);
        token1.approve(address(manager), 100_000_000 ether);

        // add 100mln token1 for liquidity. Upper tick 887000  / lower tick 886800 / liquidity minted 552324082
        (
            uint256 tokenId,
            uint128 liquidity, 
            uint256 poolBalance0_1,
            uint256 poolBalance1_1
              ) = manager.mint( 
                    INonfungiblePositionManager.MintParams({
                        token0: address(token0),
                        token1: address(token1),
                        fee: 10000,
                        tickLower: nearestUsableTick(tick_-500, 200), 
                        tickUpper:  nearestUsableTick(tick_-200, 200), 
                        amount0Desired: 0,
                        amount1Desired: 100_000_000 ether,
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: address(this),
                        deadline: _deadline
                })
        );
        counter++;
        PositionForRemove storage newPositionForRemove = positionsForRemove[counter];
        newPositionForRemove.tokenId = tokenId;
        newPositionForRemove.liquidity = liquidity;
        // console.log("tokenId", tokenId);
        // console.log("liquidity_", liquidity);
        ///////////////////////ADD LIQUIDITY END //////////////////////////////////

        uint256 swapAmount1_ = 1 ether; 
        // mint 1 token0 for second swap. 
        deal(address(token0), address(this), swapAmount1_);
        token0.approve(address(router), swapAmount1_);

        // token1.approve(address(manager), type(uint256).max);
        // token0.approve(address(manager), type(uint256).max);
        // token1.approve(address(router), type(uint256).max);
        // token0.approve(address(router), type(uint256).max);
        
        (uint256 userBalance0Before_Swap, uint256 userBalance1Before_Swap) = (
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        );
        console2.log("userBalance0Before_Swap", userBalance0Before_Swap);
        console2.log("userBalance1Before_Swap", userBalance1Before_Swap);
        // second swap. Now we drain all t1 amounts from pool for 0.066284551742012943 t0
        {
            uint256 amountOut_After_MainSWAP = router.exactInputSingle(
                IUniswapV3RouterCUTED.ExactInputSingleParams({
                    tokenIn:address(token0),
                    tokenOut:address(token1),
                    fee:10000,
                    recipient:address(this),
                    deadline: _deadline, 
                    amountIn: swapAmount1_-1000,
                    amountOutMinimum:0,
                    sqrtPriceLimitX96:0
                }) 
            );
        ///////////////////////SECOND SWAP END //////////////////////////////////

            (uint256 userBalance0After_MainSWAP, uint256 userBalance1After_MainSWAP) = (
                token0.balanceOf(address(this)),
                token1.balanceOf(address(this))
            );
            console2.log("amountOut_After_MainSWAP", amountOut_After_MainSWAP);

            console2.log("userBalance0After_MainSWAP", userBalance0After_MainSWAP);
            console2.log("userBalance1After_MainSWAP", userBalance1After_MainSWAP);
        }
        
        //last check for liquidity and moved tick
        // {
        //     require(pool.liquidity()==0, "liquidity not 0");
        //     (uint160 sqrtPriceX96_in_the_end, int24 tick_in_the_end, , , , , ) = pool.slot0();
        //     console2.log("sqrtPriceX96_in_the_end", sqrtPriceX96_in_the_end);
        //     console2.log("tick_in_the_end");
        //     console.logInt(tick_in_the_end);
        //     require(tick_in_the_end == -887272 || tick_in_the_end == -887271, "not -887272/71 tick");
        // }



        // // remove liquidity for next iteration
        
            manager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: positionsForRemove[counter].tokenId,
                    liquidity: positionsForRemove[counter].liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: _deadline
                })
            );


  
           (,,,,,,,uint128 liqudity_,,,,) = manager.positions(positionsForRemove[counter].tokenId);
            console.log("liqudity_", liqudity_);
          
    }
        



    function subtract(uint x, uint y) public pure returns(uint z) {
        z = x-y;
    }
}
