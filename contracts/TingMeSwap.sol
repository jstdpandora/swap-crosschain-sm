//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IERC20.sol";
import "./interfaces/IAggregationRouterV5.sol";
import "./interfaces/IStargateRouter.sol";
import "./access/Ownable.sol";
import "./security/Pausable.sol";
import "./libraries/SwapData.sol";
import "./libraries/BytesLib.sol";

/// This contract combines 1Inch and Stargate
contract TingMeSwap is Ownable, Pausable {
    // Constants
    // Specific address stand for NativeAddress token
    address private constant NativeAddress =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint32 private constant MILLION = 1_000_000;

    // Variables
    uint256 TingMeFee; // tingme fees (per 1,000,000)

    address vault; // TingMeFee receiver

    IAggregationRouterV5 oneInchRouter; // 1Inch router
    IStargateRouter stgRouter; // Stargate router
    mapping(uint16 => IERC20) private poolIdToToken; // mapping Stargate poolId to its token
    mapping(uint256 => bool) private isProcessedTx;

    // Events
    event Received(address indexed token, uint256 indexed amount); // emit event when user received destination token

    // Errors
    error Unauthorized();
    error InsufficientBalance(uint256 available, uint256 required);
    error WrongInput();
    error InvalidAction();

    //
    constructor(
        IAggregationRouterV5 _oneInchRouter,
        IStargateRouter _stgRouter,
        uint256 _TingMeFee,
        address _vault
    ) {
        oneInchRouter = _oneInchRouter;
        stgRouter = _stgRouter;
        TingMeFee = _TingMeFee;
        vault = _vault;
    }

    // Controller functions //

    /// @notice This function changes contract's fee
    /// @param _fee: new fee
    function changeTingMeFee(uint256 _fee) external onlyOwner whenPaused {
        TingMeFee = _fee;
    }

    /// @notice This function changes 1Inch router
    /// @param _router: new router address
    function changeOneInchRouter(IAggregationRouterV5 _router)
        external
        onlyOwner
        whenPaused
    {
        oneInchRouter = _router;
    }

    /// @notice This function changes Stargate router
    /// @param _router: new router address
    function changeSTGRouter(IStargateRouter _router)
        external
        onlyOwner
        whenPaused
    {
        stgRouter = _router;
    }

    /// @notice This function changes fee vault address
    /// @param _vault: new vault address
    function changeVault(address _vault) external onlyOwner whenPaused {
        vault = _vault;
    }

    /// @notice This function add new or update token-poolId mapping (based on Stargate)
    function changePoolToken(uint16 poolId, IERC20 token) external onlyOwner {
        poolIdToToken[poolId] = token;
    }

    /// @notice This function add new or update token-poolId mapping in batch (based on Stargate)
    function changeBatchPoolToken(Type.PoolData[] calldata pools)
        external
        onlyOwner
    {
        for (uint256 i; i < pools.length; ++i) {
            poolIdToToken[pools[i].poolId] = pools[i].token;
        }
    }

    /// @notice Owner can withdraw any tokens from this contract
    function ownerWithdraw(IERC20 token, uint256 amount) external onlyOwner {
        if (address(token) == NativeAddress) {
            if (amount > address(this).balance) {
                revert InsufficientBalance(address(this).balance, amount);
            }
            payable(msg.sender).transfer(amount);
        } else {
            token.transfer(msg.sender, amount);
        }
    }

    /// allow anyone to send native token to this contract
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

    /// @notice This function helps to create a cross chain transaction on Source Chain
    /// @dev call 1Inch API first to give srcChainSwapData and dstChainSwapData
    /// @param srcChainData: some parameter in source chain, include Stargate PoolId, swap gas fee and others
    /// @param dstChainData: some parameter in destination chain, include Stargate poolId, destination contract, remote receiver and others
    /// @param srcChainSwapData: 1Inch swap data on source chain (swap from others to stg pool token, from user to this contract)
    /// @param dstChainSwapData: 1Inch swap data on destination chain (swap from stg pool token to destination token. user is receiver)
    function swapCrosschain(
        Type.SrcChainData calldata srcChainData,
        Type.DstChainData calldata dstChainData,
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
        if (srcChainData.slippage > MILLION / 2) {
            revert WrongInput();
        }
        stgRouter.swap{value: srcChainData.fee}(
            dstChainData.chainId,
            srcChainData.poolId,
            dstChainData.poolId,
            payable(msg.sender),
            returnAmount,
            ((returnAmount * (MILLION - srcChainData.slippage)) / MILLION),
            IStargateRouter.lzTxObj(dstChainData.dstFee, 0, "0x"),
            abi.encodePacked(dstChainData.dstContract),
            data
        );
    }

    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @param dstToken: destination token
    /// @param amountIn: number of token in
    /// @param fee: fee in native token
    /// @param swapData: 1Inch data
    /// @return amount of token Out
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
        // Process others => use 1inch to swap
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
        if (TingMeFee > 0) {
            uint256 fee = (amount / MILLION) * TingMeFee;
            IERC20(token).transfer(vault, fee);
            amount -= fee;
        }

        // decode payload //
        (address to, uint32 slippage, bytes memory callSwapData) = abi.decode(
            payload,
            (address, uint32, bytes)
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
                desc.dstReceiver = payable(to);
                desc.amount = amount;
                if (slippage > MILLION / 2) slippage = MILLION / 2;
                desc.srcToken.approve(address(oneInchRouter), amount);
                desc.minReturnAmount =
                    (desc.minReturnAmount * (MILLION - slippage)) /
                    MILLION;

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
