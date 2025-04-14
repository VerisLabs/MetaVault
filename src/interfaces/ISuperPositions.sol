/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC1155A } from "./IERC1155A.sol";

interface ISuperPositions is IERC1155A {
    function mintSingle(address receiverAddress_, uint256 id_, uint256 amount_) external;

    function mintBatch(address receiverAddress_, uint256[] memory ids_, uint256[] memory amounts_) external;

    function burnSingle(address srcSender_, uint256 id_, uint256 amount_) external;

    function burnBatch(address srcSender_, uint256[] memory ids_, uint256[] memory amounts_) external;
}
