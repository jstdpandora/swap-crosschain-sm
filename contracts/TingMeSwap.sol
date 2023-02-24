//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IERC20.sol";
import "./interfaces/IAggregationRouterV5.sol";
import "./interfaces/IStargateRouter.sol";
import "./access/Ownable.sol";
import "./security/Pausable.sol";
import "hardhat/console.sol";
import "./libraries/SwapData.sol";

/// This contract combines 1Inch and Stargate
contract TingMeSwap is Ownable, Pausable {
    // Properties
    address constant Native = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 constant MILLION = 10**6;
    IAggregationRouterV5 swapRouter; // 1Inch router address
    IStargateRouter stgRouter; // StarGate router
    uint256 crosschainSwapFee; // tingme fees (per 1,000,000)
    address vault;
    mapping(uint16 => IERC20) public poolToToken;
    mapping(uint256 => bool) private isProcessed;

    // Events
    event Received(address token, uint256 amount);

    //
    constructor(
        IAggregationRouterV5 _swapRouter,
        IStargateRouter _stgRouter,
        uint256 _swapFee,
        address _vault
    ) {
        swapRouter = _swapRouter;
        stgRouter = _stgRouter;
        crosschainSwapFee = _swapFee;
        vault = _vault;
    }

    // Controller functions //

    function changeSwapFee(uint256 _fee) external onlyOwner whenPaused {
        crosschainSwapFee = _fee;
    }

    function changeSwapRouter(IAggregationRouterV5 _router)
        external
        onlyOwner
        whenPaused
    {
        swapRouter = _router;
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
        poolToToken[poolId] = token;
    }

    function rescueFunds(IERC20 token, uint256 amount) external onlyOwner {
        token.transfer(payable(msg.sender), amount);
    }

    function widthdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function destroy() external onlyOwner {
        selfdestruct(payable(msg.sender));
    }

    receive() external payable {}

    function unpause() external onlyOwner {
        _unpause();
    }

    function pause() external onlyOwner {
        _pause();
    }

    function _removeSign(bytes calldata data)
        internal
        pure
        returns (bytes memory)
    {
        return data[4:];
    }

    // Logic functions //
    function swapSingleChain(bytes calldata _data)
        external
        payable
        whenNotPaused
    {
        (
            IAggregationExecutor executor,
            Type.SwapDescription memory desc,
            bytes memory permit,
            bytes memory data
        ) = abi.decode(
                _removeSign(_data),
                (IAggregationExecutor, Type.SwapDescription, bytes, bytes)
            );
        (uint256 returnAmount, ) = swapRouter.swap{value: msg.value}(
            executor,
            desc,
            permit,
            data
        );
        if (desc.dstReceiver == address(this)) {
            if (address(desc.dstToken) == Native) {
                payable(msg.sender).transfer(returnAmount);
            } else {
                desc.dstToken.transfer(msg.sender, returnAmount);
            }
        }
    }

    function swapCrosschain(
        Type.SrcData memory srcData,
        Type.DstData memory dstData,
        bytes calldata srcCallSwapData,
        bytes calldata dstCallSwapData
    ) external payable whenNotPaused {
        if (srcCallSwapData.length == 0) {
            _swapCrosschainWithPoolToken(dstCallSwapData);
        } else {
            _swapCrosschainWithOtherToken(
                srcData,
                dstData,
                srcCallSwapData,
                dstCallSwapData
            );
        }
    }

    function _swapCrosschainWithPoolToken(bytes calldata dstData) internal {}

    function _preCroschainProcess(
        Type.SrcData memory srcData,
        bytes calldata srcCallSwapData
    ) internal returns (uint256) {
        // Decode data, ignore permit //

        (
            IAggregationExecutor srcExecutor,
            Type.SwapDescription memory srcDesc,
            ,
            bytes memory srcExecuteData
        ) = abi.decode(
                srcCallSwapData[4:],
                (IAggregationExecutor, Type.SwapDescription, bytes, bytes)
            );

        // scope validating in destination //
        {
            require(
                srcDesc.dstReceiver == address(this),
                "Token needs to be transfered to contract"
            );
            require(
                address(srcDesc.dstToken) ==
                    address(poolToToken[srcData.poolId]),
                "Target token in source chain should be supported"
            );
        }

        // Native, ERC20 process //
        uint256 nativeAmount = 0;
        if (address(srcDesc.srcToken) == Native) {
            nativeAmount = srcDesc.amount;
            require(
                nativeAmount + srcData.fee <= msg.value,
                "Native should be enough"
            );
        } else {
            srcDesc.srcToken.transferFrom(
                msg.sender,
                address(this),
                srcDesc.amount
            );
            srcDesc.srcToken.approve(address(swapRouter), srcDesc.amount);
        }
        // Swap source to pool token
        (uint256 returnAmount, ) = swapRouter.swap{value: nativeAmount}(
            srcExecutor,
            srcDesc,
            "",
            srcExecuteData
        );
        return returnAmount;
    }

    function _swapCrosschainWithOtherToken(
        Type.SrcData memory srcData,
        Type.DstData memory dstData,
        bytes calldata srcCallSwapData,
        bytes calldata dstCallSwapData
    ) internal {
        uint256 returnAmount = _preCroschainProcess(srcData, srcCallSwapData);

        // approve pool token
        {
            poolToToken[srcData.poolId].approve(
                address(stgRouter),
                returnAmount
            );
        }

        bytes memory data = abi.encode(
            dstData.to,
            dstData.slippage,
            dstCallSwapData
        );
        stgRouter.swap{value: srcData.fee}(
            dstData.chainId,
            srcData.poolId,
            dstData.poolId,
            payable(msg.sender),
            returnAmount,
            (returnAmount * srcData.slippage) / 100,
            IStargateRouter.lzTxObj(dstData.dstFee, 0, "0x"),
            abi.encodePacked(dstData.dstContract),
            data
        );
    }

    /// @param chainId The remote chainId sending the tokens
    /// @param srcAddress The remote Bridge address
    /// @param nonce: The message ordering nonce
    /// @param token: The token contract on the local chain
    /// @param amount: The qty of local token contract tokens
    /// @param payload: The swap call data in bytes
    function sgReceive(
        uint16 chainId,
        bytes memory srcAddress,
        uint256 nonce,
        address token,
        uint256 amount,
        bytes memory payload
    ) external payable {
        require(
            msg.sender == address(stgRouter),
            "Only stargate router can call sgReceive!"
        );
        require(isProcessed[nonce], "This transaction would be processed");

        // Process Fee //
        uint256 fee = (amount / MILLION) * crosschainSwapFee;
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
                ,
                IAggregationExecutor executor,
                Type.SwapDescription memory desc,
                ,
                bytes memory executeData
            ) = abi.decode(
                    callSwapData,
                    (
                        bytes4, //function hash
                        IAggregationExecutor,
                        Type.SwapDescription,
                        bytes,
                        bytes
                    )
                );
            // if wrong dstData -> transfer pool token to receiver
            if (address(desc.srcToken) != token) {
                IERC20(token).transfer(to, amount);
                emit Received(token, amount);
            }
            //
            else {
                desc.srcReceiver = payable(address(this));
                desc.dstReceiver = payable(to);
                desc.amount = amount;
                desc.minReturnAmount = (amount / MILLION) * slippage;
                (uint256 returnAmount, ) = swapRouter.swap(
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
