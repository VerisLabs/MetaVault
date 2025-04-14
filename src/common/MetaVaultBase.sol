// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ModuleBase } from "./ModuleBase.sol";
import { MultiFacetProxy } from "./MultiFacetProxy.sol";

/// @title MetaVaultBase
abstract contract MetaVaultBase is ModuleBase, MultiFacetProxy { }
