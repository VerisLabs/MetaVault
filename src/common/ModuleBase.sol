// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { IHurdleRateOracle } from "../interfaces/IHurdleRateOracle.sol";
import { ISuperformGateway } from "../interfaces/ISuperformGateway.sol";

import { ERC7540, ReentrancyGuard } from "lib/Lib.sol";
import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";

import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { VaultData, VaultLib } from "types/Lib.sol";

/// @title ModuleBase Contract for MetaVault Modules
/// @author Unlockd
/// @notice Base storage contract containing all shared state variables and helper functions for MetaVault modules
/// @dev Implements role-based access control and core vault functionality
contract ModuleBase is OwnableRoles, ERC7540, ReentrancyGuard {
    using VaultLib for VaultData;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           CONSTANTS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Maximum size of the withdrawal queue
    uint256 public constant WITHDRAWAL_QUEUE_SIZE = 30;

    /// @notice Number of seconds in a year, used for APY calculations
    uint256 public constant SECS_PER_YEAR = 31_556_952;

    /// @notice Maximum basis points (100%)
    uint256 public constant MAX_BPS = 10_000;

    /// @notice Role identifier for admin privileges
    uint256 public constant ADMIN_ROLE = _ROLE_0;

    /// @notice Role identifier for emergency admin privileges
    uint256 public constant EMERGENCY_ADMIN_ROLE = _ROLE_1;

    /// @notice Role identifier for oracle privileges
    uint256 public constant ORACLE_ROLE = _ROLE_2;

    /// @notice Role identifier for manager privileges
    uint256 public constant MANAGER_ROLE = _ROLE_3;

    /// @notice Role identifier for relayer privileges
    uint256 public constant RELAYER_ROLE = _ROLE_4;

    /// @notice Chain ID of the current network
    uint64 public THIS_CHAIN_ID;

    /// @notice Number of supported chains
    uint256 public constant N_CHAINS = 7;

    /// @dev Maximum fee that can be set (100% = 10000 basis points)
    uint16 constant MAX_FEE = 10_000;

    /// @dev Maximum time that can be set (48 hours)
    uint256 public MAX_TIME = 172_800;

    /// @notice Nonce slot seed
    uint256 internal constant _NONCES_SLOT_SEED = 0x38377508;

    /// @notice mapping from address to the average share price of their deposits
    mapping(address => uint256 averageEntryPrice) public positions;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STORAGE                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Cached value of total assets in this vault
    uint128 internal _totalIdle;
    /// @notice Cached value of total allocated assets
    uint128 internal _totalDebt;
    /// @notice Asset decimals
    uint8 _decimals;
    /// @notice Protocol fee
    uint16 public managementFee;
    /// @notice Protocol fee
    uint16 public performanceFee;
    /// @notice Protocol fee
    uint16 public oracleFee;
    /// @notice Minimum time users must wait to redeem shares
    uint24 public sharesLockTime;
    /// @notice Wether the vault is paused
    bool public emergencyShutdown;
    /// @notice Fee receiver
    address public treasury;
    /// @notice Underlying asset
    address internal _asset;
    /// @notice Signer address to process redeem requests
    address public signerRelayer;
    /// @notice Gateway contract to interact with superform
    ISuperformGateway public gateway;
    /// @notice ERC20 name
    string internal _name;
    /// @notice ERC20 symbol
    string internal _symbol;
    /// @notice maps the assets and data of each allocated vault
    /// @notice Vaults portfolio on this same chain
    uint256[WITHDRAWAL_QUEUE_SIZE] public localWithdrawalQueue;
    /// @notice Vaults portfolio in external chains
    uint256[WITHDRAWAL_QUEUE_SIZE] public xChainWithdrawalQueue;
    /// @notice Hurdle rate of underlying asset
    IHurdleRateOracle internal _hurdleRateOracle;
    /// @notice Timestamp of last report
    uint256 public lastReport;
    /// @notice Timestamp when fees were last charged globally
    uint256 public lastFeesCharged;
    /// @notice The ATH share price
    uint256 public sharePriceWaterMark;
    /// @notice The amount of assets to be considered dust by the protocol
    uint256 public dustThreshold;
    /// @notice Array of destination chain IDs
    /// @dev Includes Ethereum Mainnet, Polygon, BNB Chain, Optimism, Base, Arbitrum One, and Avalanche
    uint64[N_CHAINS] public DST_CHAINS = [
        1, // Ethereum Mainnet
        137, // Polygon
        56, // BNB Chain
        10, // Optimism
        8453, // Base
        42_161, // Arbitrum One
        43_114 // Avalanche
    ];
    /// @notice Timestamp of deposit lock
    mapping(address => uint256) internal _depositLockCheckPoint;

    /// @notice Storage of each vault related data
    mapping(uint256 => VaultData) public vaults;

    /// @notice Inverse mapping vault => superformId
    mapping(address => uint256) _vaultToSuperformId;

    /// @notice Nonce of each controller
    mapping(address controller => uint256 nonce) internal _controllerNonces;

    /// @notice Mapping of chain IDs to their respective indexes
    mapping(uint64 => uint256) internal chainIndexes;

    /// @notice Custom performance fee exemptions per controller
    mapping(address controller => uint256) public performanceFeeExempt;

    /// @notice Custom management fee exemptions per controller
    mapping(address controller => uint256) public managementFeeExempt;

    /// @notice Custom oracle fee exemptions per controller
    mapping(address controller => uint256) public oracleFeeExempt;

    /// @notice Timestamp of last redemption per controller
    mapping(address controller => uint256) public lastRedeem;

    /// @notice Number of shares that are pending to be settled;
    mapping(address controller => uint256) public pendingProcessedShares;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       HELPR FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Private helper to substract a - b or return 0 if it underflows
    function _sub0(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return a - b > a ? 0 : a - b;
        }
    }

    /// @notice Gets the shares balance of a vault in the portfolio
    /// @param data The vault data structure containing chain ID and address information
    /// @return shares The number of shares held in the vault
    /// @dev For same-chain vaults, fetches directly from the vault; for cross-chain vaults, uses Superform ERC1155
    function _sharesBalance(VaultData memory data) internal view returns (uint256 shares) {
        if (data.chainId == THIS_CHAIN_ID) {
            return ERC4626(data.vaultAddress).balanceOf(address(this));
        } else {
            return gateway.balanceOf(address(this), data.superformId);
        }
    }

    /// @dev Private helper to return `x + 1` without the overflow check.
    /// Used for computing the denominator input to `FixedPointMathLib.fullMulDiv(a, b, x + 1)`.
    /// When `x == type(uint).max`, we get `x + 1 == 0` (mod 2**256 - 1),
    /// and `FixedPointMathLib.fullMulDiv` will revert as the denominator is zero.
    function _inc_(uint256 x) internal pure returns (uint256) {
        unchecked {
            return x + 1;
        }
    }

    /// @dev Private helper to return if either value is zero.
    function _eitherIsZero_(uint256 a, uint256 b) internal pure returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := or(iszero(a), iszero(b))
        }
    }

    /// @dev Private helper get an array uint full of zeros
    /// @param len array length
    /// @return
    function _getEmptyuintArray(uint256 len) internal pure returns (uint256[] memory) {
        return new uint256[](len);
    }

    /// @notice the number of decimals of the underlying token
    function _underlyingDecimals() internal view override returns (uint8) {
        return _decimals;
    }

    /// @notice Converts a fixed-size array to a dynamic array
    /// @param arr The fixed-size array to convert
    /// @param len The length of the new dynamic array
    /// @return dynArr The converted dynamic array
    /// @dev Used to prepare data for cross-chain transactions
    function _toDynamicUint256Array(
        uint256[WITHDRAWAL_QUEUE_SIZE] memory arr,
        uint256 len
    )
        internal
        pure
        returns (uint256[] memory dynArr)
    {
        dynArr = new uint256[](len);
        for (uint256 i = 0; i < len; ++i) {
            dynArr[i] = arr[i];
        }
    }

    /// @dev Helper function to get a empty bools array
    function _getEmptyBoolArray(uint256 len) internal pure returns (bool[] memory) {
        return new bool[](len);
    }

    /// @dev Private helper to calculate shares from any @param _totalAssets
    function _convertToShares(uint256 assets, uint256 _totalAssets) internal view returns (uint256 shares) {
        if (!_useVirtualShares()) {
            uint256 supply = totalSupply();
            return _eitherIsZero_(assets, supply)
                ? _initialConvertToShares(assets)
                : Math.fullMulDiv(assets, supply, _totalAssets);
        }
        uint256 o = _decimalsOffset();
        if (o == uint256(0)) {
            return Math.fullMulDiv(assets, totalSupply() + 1, _inc_(_totalAssets));
        }
        return Math.fullMulDiv(assets, totalSupply() + 10 ** o, _inc_(_totalAssets));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CONTEXT GETTERS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function name() public view override returns (string memory) {
        return _name;
    }

    /// @notice Returns the symbol of the token.
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @notice Returns the estimate price of 1 vault share
    function sharePrice() public view returns (uint256) {
        return convertToAssets(10 ** decimals());
    }

    /// @notice Returns the base hurdle rate for performance fee calculations
    /// @dev The hurdle rate differs by asset:
    /// - For stablecoins (USDC): Typically set to T-Bills yield (e.g., 5.5% APY)
    /// - For ETH: Typically set to base staking return like Lido (e.g., 3.5% APY)
    /// @return uint256 The current base hurdle rate in basis points
    function hurdleRate() public view returns (uint256) {
        return _hurdleRateOracle.getRate(asset());
    }

    /// @notice helper function to see if a vault is listed
    function isVaultListed(address vaultAddress) public view returns (bool) {
        return _vaultToSuperformId[vaultAddress] != 0;
    }

    /// @notice helper function to see if a vault is listed
    function isVaultListed(uint256 superformId) public view returns (bool) {
        return vaults[superformId].vaultAddress != address(0);
    }

    /// @notice returns the struct containtaining vault data
    function getVault(uint256 superformId) public view returns (VaultData memory vault) {
        return vaults[superformId];
    }

    /// @notice Returns the address of the underlying asset.
    function asset() public view override returns (address) {
        return _asset;
    }

    /// @notice Returns the total amount of the underlying asset managed by the Vault.
    function totalAssets() public view override returns (uint256 assets) {
        return gateway.totalpendingXChainInvests() + gateway.totalPendingXChainDivests() + totalWithdrawableAssets();
    }

    /// @notice Returns the total amount of the underlying asset that have been deposited into the vault.
    function totalDeposits() public view returns (uint256 assets) {
        return totalIdle() + totalDebt();
    }

    /// @notice Returns the total amount of the underlying assets that are settled.
    function totalWithdrawableAssets() public view returns (uint256 assets) {
        return totalLocalAssets() + totalXChainAssets();
    }

    /// @notice Returns the total amount of the underlying asset that are located on this
    /// same chain and can be transferred synchronously
    function totalLocalAssets() public view returns (uint256 assets) {
        assets = _totalIdle;
        for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE;) {
            VaultData memory vault = vaults[localWithdrawalQueue[i]];
            if (vault.vaultAddress == address(0)) break;
            assets += vault.convertToAssets(_sharesBalance(vault), asset(), false);
            ++i;
        }
        return assets;
    }

    /// @notice Returns the total amount of the underlying asset that are located on
    /// other chains and need asynchronous transfers
    function totalXChainAssets() public view returns (uint256 assets) {
        for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE;) {
            VaultData memory vault = vaults[xChainWithdrawalQueue[i]];
            if (vault.vaultAddress == address(0)) break;
            assets += vault.convertToAssets(_sharesBalance(vault), asset(), false);
            ++i;
        }
        return assets;
    }

    /// @notice returns the assets that are sitting idle in this contract
    /// @return assets amount of idle assets
    function totalIdle() public view returns (uint256 assets) {
        return _totalIdle;
    }

    /// @notice returns the total issued debt of underlying vaulrs
    /// @return assets amount assets that are invested in vaults
    function totalDebt() public view returns (uint256 assets) {
        return _totalDebt;
    }
}
