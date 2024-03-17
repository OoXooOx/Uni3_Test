// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "./Math.sol";
import './SqrtPriceMath.sol';

library SwapMath {
    function computeSwapStep(
        uint160 sqrtPriceCurrentX96, //           last iter 5341817751600736295472531190071
        uint160 sqrtPriceTargetX96, // 1st 5550922210993867410721910935594  // last iter = 5341283623238412454227108479223
        uint128 liquidity,
        int256 amountRemaining,  // last 2-1.046612255487951413
        uint24 fee
    )
        internal
        pure
        returns (
            uint160 sqrtPriceNextX96,// 5550922210993867410721910935594  // last iter = 5341283623238412454227108479223
            uint256 amountIn, // 0.202315215108743053                    // last iter = 0.002251181215670326
            uint256 amountOut,                                          //  last iter = 10.232599950607653833
            uint256 feeAmount
        )
    {
        bool zeroForOne = sqrtPriceCurrentX96 >= sqrtPriceTargetX96;
        bool exactIn = amountRemaining >= 0;


        if (exactIn) { // true
            uint256 amountRemainingLessFee = PRBMath.mulDiv(uint256(amountRemaining), 1e6 - fee, 1e6);
            
            amountIn = zeroForOne // 0.202315215108743053 token0  // last iter 0.002251181215670326
            ? Math.calcAmount0Delta(
                sqrtPriceCurrentX96,
                sqrtPriceTargetX96,
                liquidity,
                true
            )
            : Math.calcAmount1Delta(
                sqrtPriceCurrentX96,
                sqrtPriceTargetX96,
                liquidity,
                true
            );
            if (amountRemainingLessFee >= amountIn) {  // 2 >=0.202315215108743053  //  last iter 2-1.046612255487951413 >0.002251181215670326
                sqrtPriceNextX96 = sqrtPriceTargetX96;   //  sqrtPriceNextX96 = 5550922210993867410721910935594 // last  sqrtPriceNextX96 = 5341283623238412454227108479223
            } else {
                sqrtPriceNextX96 = Math.getNextSqrtPriceFromInput(
                sqrtPriceCurrentX96,
                liquidity,
                amountRemainingLessFee,
                zeroForOne
                );
            }   
        } else {
            amountOut = zeroForOne
                ? Math.calcAmount1Delta(sqrtPriceTargetX96, sqrtPriceCurrentX96, liquidity, false)
                : Math.calcAmount0Delta(sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, false);
            if (uint256(-amountRemaining) >= amountOut) {
                sqrtPriceNextX96 = sqrtPriceTargetX96; 
            } else {
                sqrtPriceNextX96 = SqrtPriceMath.getNextSqrtPriceFromOutput(
                    sqrtPriceCurrentX96,
                    liquidity,
                    uint256(-amountRemaining),
                    zeroForOne
                );
            }
        }

        bool max = sqrtPriceNextX96 == sqrtPriceTargetX96; //  if we do 45 line, and its true. // last iter  also true 


        if (zeroForOne) {
            amountIn = max && exactIn // true && true
                ? amountIn // return this 
                : Math.calcAmount0Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, true);
            amountOut = max && !exactIn // true&& false => false
                ? amountOut
                : Math.calcAmount1Delta(sqrtPriceNextX96, sqrtPriceCurrentX96, liquidity, false); // our calculation here 
        } else {
            amountIn = max && exactIn
                ? amountIn
                : Math.calcAmount1Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, true);
            amountOut = max && !exactIn
                ? amountOut
                : Math.calcAmount0Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, false);
        }

        // cap the output amount to not exceed the remaining output amount
        if (!exactIn && amountOut > uint256(-amountRemaining)) {
            amountOut = uint256(-amountRemaining);
        }

        if (exactIn && sqrtPriceNextX96 != sqrtPriceTargetX96) {
            // we didn't reach the target, so take the remainder of the maximum input as fee
            feeAmount = uint256(amountRemaining) - amountIn;
        } else {
            feeAmount = Math.mulDivRoundingUp(amountIn, fee, 1e6 - fee);
        }
    }
}
