// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "../interfaces/IERC20.sol";

library Type {
    struct SwapDescription {
        IERC20 srcToken;
        IERC20 dstToken;
        address payable srcReceiver;
        address payable dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }

    struct SrcData {
        uint8 slippage;
        uint16 poolId;
        uint256 amountIn;
        uint256 amountOutMin;
        uint256 fee;
    }

    struct DstData {
        uint8 slippage;
        uint16 poolId;
        uint16 chainId;
        uint256 dstFee;
        address dstContract;
        address to;
    }

    struct PoolData {
        uint16 poolId;
        IERC20 token;
    }
}
