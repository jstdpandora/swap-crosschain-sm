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

    struct SrcChainData {
        uint16 poolId; // stg poolId
        uint32 slippage;
        uint256 amountIn;
        uint256 fee;
    }

    struct DstChainData {
        uint16 poolId;
        uint16 chainId;
        uint32 slippage;
        uint32 dstFee; // gas unit
        address dstContract;
        address to;
    }

    struct PoolData {
        uint16 poolId;
        IERC20 token;
    }
}
