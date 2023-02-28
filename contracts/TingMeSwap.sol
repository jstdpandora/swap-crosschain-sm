//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IERC20.sol";
import "./interfaces/IAggregationRouterV5.sol";
import "./interfaces/IStargateRouter.sol";
import "./access/Ownable.sol";
import "./security/Pausable.sol";
import "hardhat/console.sol";
import "./libraries/SwapData.sol";
import "./libraries/BytesLib.sol";

/// This contract combines 1Inch and Stargate
contract TingMeSwap is Ownable, Pausable {
    // Constants
    // Specific address stand for NativeAddress token
    address private constant NativeAddress =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 private constant MILLION = 10**6;

    // Variables
    // Fee receiver
    address vault;

    uint256 TingMeFee; // tingme fees (per 1,000,000)

    IAggregationRouterV5 oneInchRouter; // 1Inch router address
    IStargateRouter stgRouter; // StarGate router
    mapping(uint16 => IERC20) private poolIdToToken; // mapping StarGate poolId to its token
    mapping(uint256 => bool) private isProcessedTx;

    // Events
    event Received(address indexed token, uint256 indexed amount);

    // Errors
    error Unauthorized();
    error InsufficientBalance(uint256 available, uint256 required);
    error WrongInput();
    error InvalidAction();

    //
    constructor(
        IAggregationRouterV5 _oneInchRouter,
        IStargateRouter _stgRouter,
        uint256 _swapFee,
        address _vault
    ) {
        oneInchRouter = _oneInchRouter;
        stgRouter = _stgRouter;
        TingMeFee = _swapFee;
        vault = _vault;
    }

    // Controller functions //

    function changeTingMeFee(uint256 _fee) external onlyOwner whenPaused {
        TingMeFee = _fee;
    }

    function changeOneInchRouter(IAggregationRouterV5 _router)
        external
        onlyOwner
        whenPaused
    {
        oneInchRouter = _router;
    }

    function changeSTGRouter(IStargateRouter _router)
        external
        onlyOwner
        whenPaused
    {
        stgRouter = _router;
    }

    function changeVault(address _vault) external onlyOwner whenPaused {
        vault = _vault;
    }

    function changePoolToken(uint16 poolId, IERC20 token) external onlyOwner {
        poolIdToToken[poolId] = token;
    }

    function changeBatchPoolToken(Type.PoolData[] calldata pools)
        external
        onlyOwner
    {
        for (uint256 i; i < pools.length; ++i) {
            poolIdToToken[pools[i].poolId] = pools[i].token;
        }
    }

    function rescueFunds(IERC20 token, uint256 amount) external onlyOwner {
        if (address(token) == NativeAddress) {
            if (amount > address(this).balance) {
                revert InsufficientBalance(address(this).balance, amount);
            }
            payable(msg.sender).transfer(amount);
        } else {
            token.transfer(msg.sender, amount);
        }
    }

    receive() external payable {}

    function unpause() external onlyOwner {
        _unpause();
    }

    function pause() external onlyOwner {
        _pause();
    }

    function _removeFunctionSelector(bytes memory data)
        internal
        pure
        returns (bytes memory)
    {
        return BytesLib.slice(data, 4, data.length - 4);
    }

    function swapCrosschain(
        Type.SrcData calldata srcChainData,
        Type.DstData calldata dstChainData,
        bytes calldata srcChainSwapData,
        bytes calldata dstChainSwapData
    ) external payable whenNotPaused {
        IERC20 dstToken = poolIdToToken[srcChainData.poolId];
        uint256 returnAmount = _singleChainProcess(
            dstToken,
            srcChainData.amountIn,
            srcChainData.fee,
            srcChainSwapData
        );
        // approve pool token
        {
            poolIdToToken[srcChainData.poolId].approve(
                address(stgRouter),
                returnAmount
            );
        }

        bytes memory data = abi.encode(
            dstChainData.to,
            dstChainData.slippage,
            dstChainSwapData
        );

        stgRouter.swap{value: srcChainData.fee}(
            dstChainData.chainId,
            srcChainData.poolId,
            dstChainData.poolId,
            payable(msg.sender),
            returnAmount,
            (returnAmount * srcChainData.slippage) / 100,
            IStargateRouter.lzTxObj(dstChainData.dstFee, 0, "0x"),
            abi.encodePacked(dstChainData.dstContract),
            data
        );
    }

    function _singleChainProcess(
        IERC20 dstToken,
        uint256 amountIn,
        uint256 fee,
        bytes calldata swapData
    ) private returns (uint256) {
        if (swapData.length == 0) {
            // process destination token
            dstToken.transferFrom(msg.sender, address(this), amountIn);
            return amountIn;
        }
        // Process distict tokens => use 1inch to swap
        // Decode data, ignore permit //
        (
            IAggregationExecutor executor,
            Type.SwapDescription memory desc,
            ,
            bytes memory executeData
        ) = abi.decode(
                swapData[4:],
                (IAggregationExecutor, Type.SwapDescription, bytes, bytes)
            );
        // scope validating in destination //
        {
            if (
                desc.dstReceiver != address(this) ||
                address(desc.dstToken) != address(dstToken)
            ) revert WrongInput();
        }

        // NativeAddress, ERC20 process //
        uint256 nativeAmount = 0;
        if (address(desc.srcToken) == NativeAddress) {
            nativeAmount = desc.amount;
            if (nativeAmount + fee > msg.value)
                revert InsufficientBalance(msg.value, nativeAmount + fee);
        } else {
            desc.srcToken.transferFrom(msg.sender, address(this), desc.amount);
            desc.srcToken.approve(address(oneInchRouter), desc.amount);
        }
        // Swap source to pool token
        (uint256 returnAmount, ) = oneInchRouter.swap{value: nativeAmount}(
            executor,
            desc,
            "",
            executeData
        );
        return returnAmount;
    }

    /// @param chainId The remote chainId sending the tokens
    /// @param srcAddress The remote Bridge address
    /// @param nonce: The message ordering nonce
    /// @param token: The token contract on the local chain
    /// @param amount: The qty of local token contract tokens
    /// @param payload: The swap call data in bytes
    function sgReceive(
        uint16 chainId,
        bytes calldata srcAddress,
        uint256 nonce,
        address token,
        uint256 amount,
        bytes calldata payload
    ) external payable {
        if (msg.sender != address(stgRouter)) revert Unauthorized();
        if (isProcessedTx[nonce]) revert InvalidAction();

        // Process Fee //
        uint256 fee = (amount / MILLION) * TingMeFee;
        if (fee > 0) {
            IERC20(token).transfer(vault, fee);
            amount -= fee;
        }

        // decode payload //
        (address to, uint8 slippage, bytes memory callSwapData) = abi.decode(
            payload,
            (address, uint8, bytes)
        );
        // check swap //
        if (callSwapData.length == 0) {
            // transfer directly
            IERC20(token).transfer(to, amount);
            emit Received(token, amount);
        } else {
            // decode data
            (
                IAggregationExecutor executor,
                Type.SwapDescription memory desc,
                ,
                bytes memory executeData
            ) = abi.decode(
                    _removeFunctionSelector(callSwapData),
                    (IAggregationExecutor, Type.SwapDescription, bytes, bytes)
                );
            // if wrong dstChainData -> transfer pool token to receiver
            if (address(desc.srcToken) != token) {
                IERC20(token).transfer(to, amount);
                emit Received(token, amount);
            }
            //
            else {
                desc.srcReceiver = payable(to);
                desc.dstReceiver = payable(to);
                desc.amount = amount;
                desc.minReturnAmount = (amount / MILLION) * slippage;
                (uint256 returnAmount, ) = oneInchRouter.swap(
                    executor,
                    desc,
                    "",
                    executeData
                );
                emit Received(address(desc.dstToken), returnAmount);
            }
        }
    }
}
