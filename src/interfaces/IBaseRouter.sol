/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "types/Lib.sol";

interface IBaseRouter {
    function singleDirectSingleVaultDeposit(SingleDirectSingleVaultStateReq memory req_) external payable;

    function singleXChainSingleVaultDeposit(SingleXChainSingleVaultStateReq memory req_) external payable;

    function singleDirectMultiVaultDeposit(SingleDirectMultiVaultStateReq memory req_) external payable;

    function singleXChainMultiVaultDeposit(SingleXChainMultiVaultStateReq memory req_) external payable;

    function multiDstSingleVaultDeposit(MultiDstSingleVaultStateReq calldata req_) external payable;

    function multiDstMultiVaultDeposit(MultiDstMultiVaultStateReq calldata req_) external payable;

    function singleDirectSingleVaultWithdraw(SingleDirectSingleVaultStateReq memory req_) external payable;

    function singleXChainSingleVaultWithdraw(SingleXChainSingleVaultStateReq memory req_) external payable;

    function singleDirectMultiVaultWithdraw(SingleDirectMultiVaultStateReq memory req_) external payable;

    function singleXChainMultiVaultWithdraw(SingleXChainMultiVaultStateReq memory req_) external payable;

    function multiDstSingleVaultWithdraw(MultiDstSingleVaultStateReq calldata req_) external payable;

    function multiDstMultiVaultWithdraw(MultiDstMultiVaultStateReq calldata req_) external payable;

    function forwardDustToPaymaster(address token_) external;
}
