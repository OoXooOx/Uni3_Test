// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


import "../interfaces/IFlashLoanRecipient.sol";
import "../interfaces/IBalancerVault.sol";

import "../interfaces/INonfungiblePositionManagerCUTED.sol";
import "../interfaces/IUniswapV3PoolCUTED.sol";
import "../interfaces/IUniswapV3RouterCUTED.sol";
import "../lib/ABDKMath64x64.sol";

contract USDCLUSD {
   
    address public constant vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8; 
    address public constant keeper = 0x0896d73E0E978696a3ae5fe2e17ebDD8F6982729;

    INonfungiblePositionManagerCUTED manager = INonfungiblePositionManagerCUTED(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IUniswapV3PoolCUTED pool = IUniswapV3PoolCUTED(0x53A509d1cF1de11B418e82DaC58c0648a0fdaFCA);
    IUniswapV3RouterCUTED router = IUniswapV3RouterCUTED(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IERC20  token0 = IERC20(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0);
    IERC20  token1 = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    //////// CHECK deadline 18/03/2024
    uint deadline = 1710753303;
    struct PositionForRemove {
        uint tokenId;
        uint128 liquidity;
    }
    mapping(uint=>PositionForRemove) positionsForRemove;
    uint counter;


    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external {
        // work(); 
        
        for (uint256 i; i < tokens.length; ) {
            IERC20 token = tokens[i];
            uint256 amount = amounts[i];
            
            disadvantage(token, amount);

         
            uint256 feeAmount = feeAmounts[i];
         

            // Return loan
            token.transfer(vault, amount);

            unchecked {
                ++i;
            }
        }
    }

    function flashLoanPrimary() external {
        IERC20[] memory tokens = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = token1;
        amounts[0] = 10_010 * 10**6;
        
        
        token1.approve(address(manager), type(uint256).max);
        token0.approve(address(manager), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        token0.approve(address(router), type(uint256).max);

        addLiquidity1000weiOfToken0(deadline);
    
        //how many jumps of work you need
        uint interactions = 3;
        for(uint i; i < interactions; ){
            IBalancerVault(vault).flashLoan(
                IFlashLoanRecipient(address(this)),
                tokens,
                amounts,
                ""
            );

            unchecked {
                ++i;
            }
        } 
    }

    function flashLoanSecondary() external {
        IERC20[] memory tokens = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = token1;
        amounts[0] = 10_010 * 10**6;
        
        token1.approve(address(manager), type(uint256).max);
        token0.approve(address(manager), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        token0.approve(address(router), type(uint256).max);
    
        //how many jumps of work you need
        uint interactions = 5;
        for(uint i; i < interactions; ){
            IBalancerVault(vault).flashLoan(
                IFlashLoanRecipient(address(this)),
                tokens,
                amounts,
                ""
            );

            unchecked {
                ++i;
            }
        } 
    }

    function disadvantage(IERC20 token, uint256 amount) internal {
        uint256 currentAmount = token.balanceOf(address(this));

        if(currentAmount < amount) {
            uint256 missingQuantity = amount - currentAmount;

            token.transferFrom(keeper, address(this), missingQuantity);
        }
    }

    //SC must has at least 1e18/1e18 of token0/token1  
    function work() public {
        //we need approve some amounts of token0
        uint256 swapAmount = 1 ether; 
        // SC  must have now 1(1e18) token1 for first swap. 
        // We move price to upper boundary
        swap1ofToken1(deadline);

        //check that we are in upper boundary
        (,int24 tick, , , , , ) = pool.slot0();
        require(tick==887271 || tick==887272, "not 887271/72 tick");

        // add 100mln token1 for liquidity. 
        // Upper tick 887000  / lower tick 886800 / 
        addLiquidity100mlnToken1(deadline, tick);

        // final swap. Now we withdraw all t1 amounts from pool 
        // for 0.066284551742012943 t0
        finalSwap(deadline, swapAmount);

        //we need remove dust otherwise we can't move tick to upper boundary
        removeLiquidity();    
    }

    function removeLiquidity() public {
        manager.decreaseLiquidity(
            INonfungiblePositionManagerCUTED.DecreaseLiquidityParams({
                tokenId: positionsForRemove[counter].tokenId,
                liquidity: positionsForRemove[counter].liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: deadline
            })
        );
    }


    function swap1ofToken1(uint256 _deadline) public {

        uint256 amountOut = router.exactInputSingle(
            IUniswapV3RouterCUTED.ExactInputSingleParams({
                tokenIn:address(token1),
                tokenOut:address(token0),
                fee:10000,
                recipient:address(this),
                deadline: _deadline,
                amountIn: 1 ether,
                amountOutMinimum:0,
                sqrtPriceLimitX96:0
            }) 
        ); 
    }

    function addLiquidity1000weiOfToken0(uint256 _deadline) public {
        (, int24 tick, , , , , ) = pool.slot0();//  -276000
        int24 upperTick =  nearestUsableTick(tick+500, 200); //-275600
        if(upperTick>887200) upperTick=887200;
            (
            uint256 tokenId,
            uint128 liquidity_, 
            uint256 poolBalance0_1,
            uint256 poolBalance1_1
              ) = manager.mint( 
                    INonfungiblePositionManagerCUTED.MintParams({
                        token0: address(token0),
                        token1: address(token1),
                        fee: 10000, 
                        tickLower: nearestUsableTick(upperTick-200, 200),  //-//-275800
                        tickUpper:  upperTick, ////-275600
                        amount0Desired: 1 ether,
                        amount1Desired: 0,
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: address(this),
                        deadline: _deadline 
                })
        );
    }

    function addLiquidity100mlnToken1(uint _deadline, int24 _tick) public {

        (
            uint256 tokenId,
            uint128 liquidity, 
            uint256 poolBalance0,
            uint256 poolBalance1
              ) = manager.mint( 
                    INonfungiblePositionManagerCUTED.MintParams({
                        token0: address(token0),
                        token1: address(token1),
                        fee: 10000,
                        tickLower: nearestUsableTick(_tick-500, 200), 
                        tickUpper:  nearestUsableTick(_tick-200, 200), 
                        amount0Desired: 0,
                        amount1Desired: 100_000 ether,
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: address(this),
                        deadline: _deadline
                })
        );
        //we need track added liquidity position
        counter++;
        PositionForRemove storage newPositionForRemove = positionsForRemove[counter];
        newPositionForRemove.tokenId = tokenId;
        newPositionForRemove.liquidity = liquidity;
    }

    function finalSwap(uint _deadline, uint _swapAmount) public { 
 
        uint256 amountOut = router.exactInputSingle(
            IUniswapV3RouterCUTED.ExactInputSingleParams({
                tokenIn:address(token0),
                tokenOut:address(token1),
                fee:10000,
                recipient:address(this),
                deadline: _deadline,
                amountIn: _swapAmount-1000,
                amountOutMinimum:0,
                sqrtPriceLimitX96:0
            }) 
        ); 
    }

    //////////////////////////////HELPERS////////////////////////////////////

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    function nearestUsableTick(int24 tick_, uint24 tickSpacing)
        internal
        pure
        returns (int24 result)
    {
        result =
            int24(divRound(int128(tick_), int128(int24(tickSpacing)))) *
            int24(tickSpacing);

        if (result < MIN_TICK) {
            result += int24(tickSpacing);
        } else if (result > MAX_TICK) {
            result -= int24(tickSpacing);
        }
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
}
