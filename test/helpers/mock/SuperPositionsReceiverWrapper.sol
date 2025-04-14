// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { SuperPositionsReceiver } from "src/crosschain/SuperPositionsReceiver.sol";

contract SuperPositionsReceiverWrapper is SuperPositionsReceiver {
    constructor(
        uint64 _sourceChain,
        address _gateway,
        address _superPositions,
        address _owner
    )
        SuperPositionsReceiver(_sourceChain, _gateway, _superPositions, _owner)
    { }

    function getChainId() external view returns (uint256) {
        return block.chainid;
    }
}
