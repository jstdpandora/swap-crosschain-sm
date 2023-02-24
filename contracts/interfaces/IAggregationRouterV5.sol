// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "./IAggregationExecutor.sol";
import "./IERC20.sol";
import "../libraries/SwapData.sol";

interface IAggregationRouterV5 {
    function swap(
        IAggregationExecutor executor,
        Type.SwapDescription calldata desc,
        bytes calldata permit,
        bytes calldata data
    ) external payable returns (uint256 returnAmount, uint256 spentAmount);
}
