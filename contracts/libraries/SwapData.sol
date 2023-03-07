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

    struct StgData {
        uint16 srcChainPoolId;
        uint16 dstChainPoolId;
        uint16 dstChainId;
        uint32 dstChainGasUnit;
        uint256 totalGasFee;
    }

    struct TxData {
        uint32 slippage;
        address receiver;
        uint256 amountIn;
        address dstChainTingMeContract;
    }

    struct PoolData {
        uint16 poolId;
        IERC20 token;
    }
}
