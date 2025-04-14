// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { Multicallable } from "solady/utils/Multicallable.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { MetaVaultBase, MultiFacetProxy } from "common/Lib.sol";

import { IHurdleRateOracle, ISharePriceOracle, ISuperformGateway } from "interfaces/Lib.sol";
import { NoDelegateCall } from "lib/Lib.sol";
import { VaultConfig, VaultData, VaultLib, VaultReport } from "types/Lib.sol";

//                                              XXSSNNNNNNNNSS
//                                        XSEAAAAAAAAAAAAAAAAAAAAAJSS
//                                    XEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJX
//                                 SAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAX
//                              XAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEN
//                            SAAAAAAAAAAAAAAAAAAAAAA  AAAAAAAAAAAAAAAAAAAAAAAAAS
//                          SAAAAAAAAAAAAAAAAAAAAAAA  AAAJX      NAAAAAAAAAAAAAAAAX
//                         AAAAAAJ         XNAAAAEJJ XS NAAAAAAAJ   SEAAAAAAAAAAE AA
//                       NAAAAAX   XSSS               X  A   AAAAAJX         SNA NAAAX
//              XS      EAAAAA XAAX  XSEEX            ENSJAAAAAAEX N          ESXAAAAAJ
//             AAAASSSXAAAAAANANAE SES                      SJENX   E       SAN ASAAAAAA
//       XNJEAJAAAAX  AAAAAAAA  AJN          XNJJJJJJJJSX         SSES      SEJENXAAAAAAA
//     AAENJ    XS   AAAAAAAANEAN       SAAAAAAAAAAAAEEJEAAAEN                   SAAAAAAAE
//   EAN            JAAAAAAAA E      JAAAAAAAAAAAAAAAAAAENSX NEAAN               NAAAAAAAAS
//  AAS             AAAAAAAAAN    JAAAAAAAAAAAAAAAAAAAAAAAAAA    JAAJ            JAAAAAAAAA
//  AA             AAAAAAAAAN   EAAAAAAAAAAAAAAAAAAS  XXSJEAAAAE   XAAJX      JEEEAAAAAAAAAN
//  AAS            AAAAAAAAJ  NAAAAAAAS     XJAAA           SJAAAAX  SAAJX  SAAES   NAAAAAAA
//  EAAS          JAAAAAAAA  AAAAAAAX          N              XNEAAANNAAAASXAA        EAAAAA
//   AAAE         AAAAAAAASSAAAAAAA                XX           XJAAAAAAAAAAA     SJJX JAAAAN
//    NAAAJ       AAAAAAAAAAAAAAAAA         NSXXNNS EAJX           XJAAAAAAAA    XXXXJE AAAAE
//      AAAAEX    AAAAAAAA  JAAAN  SN NJJ    A     SAAA  SN           SEAAAAA    XXXXXA JAAAA
//       SAAAAAJS AAAAAAAX   AAAAJ    JAA    A      XAEX                SAAAA    XXXXXA NAAAA
//          AAAAAAAAAAAAAN  JAAAAA    XJ       XXXXXSX                   SEAAN    XXXNJ AAAAE  X
//           XNAAAAAAAAAAAAAAAAAAANXX   NS     XJ                         SAAA     XN   AAAA     JX
//              XAAAAAAAA XXAAAAAAA     S                                  EAAAN       AAAAA       AS
//                 AAAAAA   AAAAAAX                    XXSX   XXN          EAAJAAANXNAAAAAAE        NAX
//                 XAAAAA   AAAAAJ               XXXS       S  XJ         NAAE  SJNAAAAAAAA           AJ
//                  EAAAAE   AAAJ                         S  SSX        XEAAE    XEAAAAAAAN            AA
//                   AAAAA   AAAA             XNJ X      XSXX          XEAAJ    NAAAAAAAAA              AA
//                    AAAAA   AAAS                  XNSS             XJAAA    SEAAAAAAAAA               AA
//                    SAAAAA  NAAAJX                               SJAAAN   XEAAAAAAAAAA                AA
//                     SAAAAAX XAAAAAAE                         XJAAAAE   SEAAAAAAAAAAA              NSAAN
//                      XEAAAAA  EAAAAAAE                     NEAAAAX   JAAAAAAAAAAAAN          SSSNAAAAN
//                        NAAAAAAX SAAAAAAAAJX            NEAAAAEX   NAAAAAAAAAAAAAAAAAEJEAAAAAAAAAAAN
//                         XEAAAAAAASSEAAAAAAAAAAAAAAAAAAAAAJX   SEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJJSX
//                           NJAAAAAAAAAAAAAAAAAAAAAAAAENNSSJAAAAAAAAAAAAAAAAAAASSNNNNNNSSSSX
//                              SJAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJX
//                                XNAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAS
//                                   SNJAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJS
//                                     ASSSNNEAAAAAAAAAAAAAAAAAAAAENX
//                                           X     XSSNNNNNNNSSX

/// @title MetaVault
/// @author Unlockd
/// @notice A ERC750 vault implementation for cross-chain yield
/// aggregation
contract MetaVault is MetaVaultBase, Multicallable, NoDelegateCall {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           LIBRARIES                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Safe casting operations for uint
    using SafeCastLib for uint256;

    /// @dev Safe transfer operations for ERC20 tokens
    using SafeTransferLib for address;

    /// @dev Library for vault-related operations
    using VaultLib for VaultData;

    /// @dev Library for math
    using Math for uint256;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Emitted when fees are applied to a user
    event AssessFees(address indexed controller, uint256 managementFees, uint256 performanceFees, uint256 oracleFees);

    /// @dev Emitted when adding a new vault to the portfolio
    event AddVault(uint64 indexed chainId, address vault);

    /// @dev Emitted when removing a vault from the portfolio
    event RemoveVault(uint64 indexed chainId, address vault);

    /// @dev Emitted when updating the shares lock time
    event SetSharesLockTime(uint24 time);

    /// @dev Emitted when updating the management fee
    event SetManagementFee(uint16 fee);

    /// @dev Emitted when updating the performance fee
    event SetPerformanceFee(uint16 fee);

    /// @dev Emitted when updating the oracle fee
    event SetOracleFee(uint16 fee);

    /// @dev Emitted when the emergency shutdown state is changed
    event EmergencyShutdown(bool enabled);

    /// @dev Emitted when the treasury address is updated
    event TreasuryUpdated(address indexed treasury);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Thrown when attempting to rearrange with invalid queue type
    error InvalidQueueType();

    /// @notice Thrown when new queue order contains duplicate vaults
    error DuplicateVaultInOrder();

    /// @notice Thrown when new queue order has different number of vaults than current queue
    error VaultCountMismatch();

    /// @notice Thrown when new queue order is missing vaults from current queue
    error MissingVaultFromCurrentQueue();

    /// @notice Thrown when new queue order contains vaults not in current queue
    error NewVaultNotInCurrentQueue();

    /// @notice Thrown when attempting to add a vault that is already listed
    error VaultAlreadyListed();

    /// @notice Thrown when attempting to withdraw more assets than are currently available
    error InsufficientAvailableAssets();

    /// @notice Thrown when trying to perform an operation on a request that has not been settled yet
    error RequestNotSettled();

    /// @notice Thrown when trying to redeem a non processed request
    error RedeemNotProcessed();

    /// @notice Thrown when attempting to redeem shares that are still locked
    error SharesLocked();

    /// @notice Thrown when attempting to perform an operation while the vault is in emergency shutdown
    error VaultShutdown();

    /// @notice Thrown when attempting to to remove a vault that is still in the metavault balance
    error SharesBalanceNotZero();

    /// @notice Thrown when attempting to operate on an invalid superform ID
    error InvalidSuperformId();

    /// @notice Thrown when attempting to add a vault with invalid address
    error InvalidVaultAddress();

    /// @notice Thrown when the maximum queue size is exceeded
    error MaxQueueSizeExceeded();

    /// @notice Thrown when an invalid zero address is encountered
    error InvalidZeroAddress();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           MODIFIERS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Modifier to prevent execution during emergency shutdown
    /// @dev Reverts the transaction if emergencyShutdown is true
    modifier noEmergencyShutdown() {
        if (emergencyShutdown) {
            revert VaultShutdown();
        }
        _;
    }

    /// @notice Modifier to update the share price water-mark after running a function
    /// @dev Updates the high water mark if the current share price exceeds the previous mark
    modifier updateGlobalWatermark() {
        _;
        uint256 sp = sharePrice();
        assembly {
            let spwm := sload(sharePriceWaterMark.slot)
            if lt(spwm, sp) { sstore(sharePriceWaterMark.slot, sp) }
        }
    }

    /// @notice Constructor for the MetaVault contract
    /// @param config The initial configuration parameters for the vault
    constructor(VaultConfig memory config) MultiFacetProxy(ADMIN_ROLE) {
        _asset = config.asset;
        _name = config.name;
        _symbol = config.symbol;
        treasury = config.treasury;
        isOperator[treasury][address(this)] = true;
        emit OperatorSet(treasury, address(this), true);
        managementFee = config.managementFee;
        performanceFee = config.performanceFee;
        oracleFee = config.oracleFee;
        sharesLockTime = config.sharesLockTime;
        lastReport = block.timestamp;
        _hurdleRateOracle = config.hurdleRateOracle;

        // Try to get asset decimals, fallback to default if unsuccessful
        (bool success, uint8 result) = _tryGetAssetDecimals(config.asset);
        _decimals = success ? result : _DEFAULT_UNDERLYING_DECIMALS;
        // Set the chain ID for the current network
        THIS_CHAIN_ID = uint64(block.chainid);
        // Initialize chainIndexes mapping
        for (uint256 i = 0; i != N_CHAINS; i++) {
            chainIndexes[DST_CHAINS[i]] = i;
        }

        lastFeesCharged = block.timestamp;

        // Initialize ownership and grant admin role
        _initializeOwner(config.owner);
        _grantRoles(config.owner, ADMIN_ROLE);

        // Initialize signer relayer
        signerRelayer = config.signerRelayer;

        // Set initial watermark
        sharePriceWaterMark = 10 ** decimals();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ERC7540 ACTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Transfers assets from sender into the Vault and submits a Request for asynchronous deposit.
    /// @param assets the amount of deposit assets to transfer from owner
    /// @param controller the controller of the request who will be able to operate the request
    /// @param owner the owner of the shares to be deposited
    /// @return requestId
    function requestDeposit(
        uint256 assets,
        address controller,
        address owner
    )
        public
        override
        noDelegateCall
        noEmergencyShutdown
        returns (uint256 requestId)
    {
        if (owner != msg.sender) revert InvalidOperator();
        requestId = super.requestDeposit(assets, controller, owner);
        // fulfill the request directly
        _fulfillDepositRequest(controller, assets, convertToShares(assets));
    }

    /// @notice Mints shares Vault shares to receiver by claiming the Request of the controller.
    /// @dev uses msg.sender as controller
    /// @param shares to mint
    /// @param to shares receiver
    /// @return shares minted shares
    function deposit(uint256 assets, address to) public override returns (uint256 shares) {
        return deposit(assets, to, msg.sender);
    }

    /// @notice Mints shares Vault shares to receiver by claiming the Request of the controller.
    /// @param assets to mint
    /// @param to shares receiver
    /// @param controller controller address
    /// @return shares minted shares
    function deposit(
        uint256 assets,
        address to,
        address controller
    )
        public
        override
        noDelegateCall
        noEmergencyShutdown
        returns (uint256 shares)
    {
        uint256 sharesBalance = balanceOf(to);
        shares = super.deposit(assets, to, controller);
        // Start shares lock time
        _lockShares(controller, sharesBalance, shares);
        _afterDeposit(assets, shares);
        return shares;
    }

    /// @notice Mints exactly shares Vault shares to receiver by claiming the Request of the controller.
    /// @dev uses msg.sender as controllerisValidSignat
    /// @param shares to mint
    /// @param to shares receiver
    /// @return assets deposited assets
    function mint(uint256 shares, address to) public override returns (uint256 assets) {
        return mint(shares, to, msg.sender);
    }

    /// @notice Mints exactly shares Vault shares to receiver by claiming the Request of the controller.
    /// @param shares to mint
    /// @param to shares receiver
    /// @param controller controller address
    /// @return assets deposited assets
    function mint(
        uint256 shares,
        address to,
        address controller
    )
        public
        override
        noDelegateCall
        noEmergencyShutdown
        returns (uint256 assets)
    {
        uint256 sharesBalance = balanceOf(to);
        assets = super.mint(shares, to, controller);
        _lockShares(controller, sharesBalance, shares);
        _afterDeposit(assets, shares);
    }

    /// @dev Override to update the average entry price and the timestamp of last redeem
    function _deposit(
        uint256 assets,
        uint256 shares,
        address receiver,
        address controller
    )
        internal
        override
        returns (uint256 assetsReturn, uint256 sharesReturn)
    {
        _updatePosition(controller, shares);
        if (lastRedeem[controller] == 0) lastRedeem[controller] = block.timestamp;
        return super._deposit(assets, shares, receiver, controller);
    }

    /// @notice Assumes control of shares from sender into the Vault and submits a Request for asynchronous redeem.
    /// @param shares the amount of shares to be redeemed to transfer from owner
    /// @param controller the controller of the request who will be able to operate the request
    /// @param owner the source of the shares to be redeemed
    /// @return requestId id
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    )
        public
        override
        noDelegateCall
        noEmergencyShutdown
        returns (uint256 requestId)
    {
        // Require deposited shares arent locked
        _checkSharesLocked(controller);
        requestId = super.requestRedeem(shares, controller, owner);
    }

    /// @dev Redeems shares for assets, ensuring all settled requests are fulfilled
    /// @param shares The number of shares to redeem
    /// @param receiver The address that will receive the assets
    /// @param controller The address that controls the redemption
    /// @return assets The amount of assets redeemed
    function redeem(
        uint256 shares,
        address receiver,
        address controller
    )
        public
        override
        noDelegateCall
        nonReentrant
        returns (uint256 assets)
    {
        assets = super.redeem(shares, receiver, controller);
    }

    /// @dev Withdraws assets, ensuring all settled requests are fulfilled
    /// @param assets The amount of assets to withdraw
    /// @param receiver The address that will receive the assets
    /// @param controller The address that controls the withdrawal
    /// @return shares The number of shares burned
    function withdraw(
        uint256 assets,
        address receiver,
        address controller
    )
        public
        override
        noDelegateCall
        nonReentrant
        returns (uint256 shares)
    {
        return super.withdraw(assets, receiver, controller);
    }

    struct TempWithdrawData {
        uint256 entrySharePrice;
        uint256 currentSharePrice;
        int256 assetsDelta;
        uint256 duration;
        uint256 performanceFeeExempt;
        uint256 managementFeeExempt;
        uint256 oracleFeeExempt;
        uint256 performanceFees;
        uint256 managementFees;
        uint256 oracleFees;
        uint256 totalFees;
    }

    /// @dev Override to apply fees on exit
    function _withdraw(
        uint256 assets,
        uint256 shares,
        address receiver,
        address controller
    )
        internal
        override
        returns (uint256 assetsReturn, uint256 sharesReturn)
    {
        TempWithdrawData memory temp;
        // Get the price metrics needed for calculations
        temp.entrySharePrice = positions[controller];
        temp.currentSharePrice = sharePrice();

        // Consume claimable
        unchecked {
            _claimableRedeemRequest[controller].assets -= assets;
            _claimableRedeemRequest[controller].shares -= shares;
        }

        temp.duration = block.timestamp - Math.max(lastRedeem[controller], lastFeesCharged);
        lastRedeem[controller] = block.timestamp;

        // Get fee exemptions for this controller
        temp.performanceFeeExempt = performanceFeeExempt[controller];
        temp.managementFeeExempt = managementFeeExempt[controller];
        temp.oracleFeeExempt = oracleFeeExempt[controller];

        // Calculate time-based fees (management & oracle)
        // These are charged on total assets, prorated for the time period
        temp.managementFees =
            (assets * temp.duration).fullMulDiv(_sub0(managementFee, temp.managementFeeExempt), SECS_PER_YEAR) / MAX_BPS;
        temp.oracleFees =
            (assets * temp.duration).fullMulDiv(_sub0(oracleFee, temp.oracleFeeExempt), SECS_PER_YEAR) / MAX_BPS;
        assets -= temp.managementFees + temp.oracleFees;
        temp.totalFees += temp.managementFees + temp.oracleFees;

        // Calculate the asset's value change since entry
        // This gives us the raw profit/loss in asset terms
        temp.assetsDelta = int256(assets) - (int256(shares) * int256(temp.entrySharePrice) / int256(10 ** decimals()));

        // Only calculate fees if there's a profit
        if (temp.assetsDelta > 0) {
            uint256 totalReturn = uint256(temp.assetsDelta);
            // Calculate returns relative to hurdle rate
            uint256 hurdleReturn = (assets * hurdleRate()).fullMulDiv(temp.duration, SECS_PER_YEAR) / MAX_BPS;
            uint256 excessReturn;

            // Only charge performance fees if:
            // 1. Current share price is not below
            // 2. Returns exceed hurdle rate
            if (temp.currentSharePrice > sharePriceWaterMark && totalReturn > hurdleReturn) {
                // Only charge performance fees on returns above hurdle rate
                excessReturn = totalReturn - hurdleReturn;

                temp.performanceFees = excessReturn * _sub0(performanceFee, temp.performanceFeeExempt) / MAX_BPS;
            }
            // Calculate total fees
            temp.totalFees += temp.performanceFees;
        }

        // Transfer fees to treasury if any were charged
        if (temp.totalFees > 0) {
            // mint shares for treasury
            _mint(treasury, convertToShares(temp.totalFees));
            _afterDeposit(temp.totalFees, 0);
        }

        // Transfer remaining assets to receiver
        uint256 totalAssetsAfterFee = assets - temp.totalFees;
        asset().safeTransfer(receiver, totalAssetsAfterFee);

        {
            uint256 managementFees = temp.managementFees;
            uint256 performanceFees = temp.performanceFees;
            uint256 oracleFees = temp.oracleFees;
            // Emit events
            /// @solidity memory-safe-assembly
            assembly {
                let mp := mload(0x40) // Grab the free memory pointer.
                // Emit the {Withdraw} event
                mstore(0x00, totalAssetsAfterFee)
                mstore(0x20, shares)
                let m := shr(96, not(0))
                log4(
                    0x00,
                    0x40,
                    0xfbde797d201c681b91056529119e0b02407c7bb96a4a2c75c01fc9667232c8db,
                    and(m, controller),
                    and(m, receiver),
                    and(m, controller)
                )
                // Emit the {AssessFees} event
                mstore(0x00, managementFees)
                mstore(0x20, performanceFees)
                mstore(0x40, oracleFees)
                log2(0x00, 0x60, 0xa443e1db11cb46c65620e8e21d4830a6b9b444fa4c350f0dd0024b8a5a6b6ef5, and(m, controller))
                mstore(0x40, mp) // Restore the free memory pointer.
                mstore(0x60, 0) // Restore the zero pointer.
            }
        }

        return (totalAssetsAfterFee, shares);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VAULT MANAGEMENT                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @notice Charges global management, performance, and oracle fees on the vault's total assets
    /// @dev Fee charging mechanism works as follows:
    /// 1. Time-based fees (management & oracle) are charged on total assets, prorated for the time period
    /// 2. Performance fees are only charged if two conditions are met:
    ///    a) Current share price is above the watermark (high water mark)
    ///    b) Returns exceed the hurdle rate
    /// 3. The hurdle rate is asset-specific:
    ///    - For stablecoins (e.g., USDC): typically tied to T-Bill yields
    ///    - For ETH: typically tied to base staking returns (e.g., Lido APY)
    /// 4. Performance fees are only charged on excess returns above both:
    ///    - The watermark (preventing double-charging on same gains)
    ///    - The hurdle rate (ensuring fees only on excess performance)
    /// Example calculation:
    /// - If initial assets = $1M, current assets = $1.08M
    /// - Duration = 180 days, Management = 2%, Oracle = 0.5%, Performance = 20%
    /// - Hurdle = 5% APY
    /// Then:
    /// 1. Management Fee = $1.08M * 2% * (180/365) = $10,628
    /// 2. Oracle Fee = $1.08M * 0.5% * (180/365) = $2,657
    /// 3. Hurdle Return = $1M * 5% * (180/365) = $24,657
    /// 4. Excess Return = ($80,000 - $13,285 - $24,657) = $42,058
    /// 5. Performance Fee = $42,058 * 20% = $8,412
    /// @return uint256 Total fees charged
    function chargeGlobalFees() external updateGlobalWatermark onlyRoles(MANAGER_ROLE) returns (uint256) {
        uint256 currentSharePrice = sharePrice();
        uint256 lastSharePrice = sharePriceWaterMark;
        uint256 duration = block.timestamp - lastFeesCharged;
        uint256 currentTotalAssets = totalAssets();
        uint256 lastTotalAssets = totalSupply().fullMulDiv(lastSharePrice, 10 ** decimals());

        // Calculate time-based fees (management & oracle)
        // These are charged on total assets, prorated for the time period
        uint256 managementFees = (currentTotalAssets * duration).fullMulDiv(managementFee, SECS_PER_YEAR) / MAX_BPS;
        uint256 oracleFees = (currentTotalAssets * duration).fullMulDiv(oracleFee, SECS_PER_YEAR) / MAX_BPS;
        uint256 totalFees = managementFees + oracleFees;
        uint256 performanceFees;

        currentTotalAssets += managementFees + oracleFees;

        lastFeesCharged = block.timestamp;

        // Calculate the asset's value change since entry
        // This gives us the raw profit/loss in asset terms
        int256 assetsDelta = int256(currentTotalAssets) - int256(lastTotalAssets);

        // Only calculate fees if there's a profit
        if (assetsDelta > 0) {
            uint256 excessReturn;

            // Calculate returns relative to hurdle rate
            uint256 hurdleReturn = (lastTotalAssets * hurdleRate()).fullMulDiv(duration, SECS_PER_YEAR) / MAX_BPS;
            uint256 totalReturn = uint256(assetsDelta);

            // Only charge performance fees if:
            // 1. Current share price is not below
            // 2. Returns exceed hurdle rate
            if (currentSharePrice > sharePriceWaterMark && totalReturn > hurdleReturn) {
                // Only charge performance fees on returns above hurdle rate
                excessReturn = totalReturn - hurdleReturn;

                performanceFees = excessReturn * performanceFee / MAX_BPS;
            }

            // Calculate total fees
            totalFees += performanceFees;
        }
        // Transfer fees to treasury if any were charged
        if (totalFees > 0) {
            _mint(treasury, convertToShares(totalFees));
        }
        /// @solidity memory-safe-assembly
        assembly {
            let mp := mload(0x40) // Grab the free memory pointer.
            let m := shr(96, not(0))

            // Emit the {AssessFees} event
            mstore(0x00, managementFees)
            mstore(0x20, performanceFees)
            mstore(0x40, oracleFees)
            log2(0x00, 0x60, 0xa443e1db11cb46c65620e8e21d4830a6b9b444fa4c350f0dd0024b8a5a6b6ef5, and(m, address()))
            mstore(0x40, mp) // Restore the free memory pointer.
            mstore(0x60, 0) // Restore the zero pointer.
        }
        return totalFees;
    }

    /// @notice Add a new vault to the portfolio
    /// @param chainId chainId of the vault
    /// @param superformId id of superform
    /// @param vault vault address
    /// @param vaultDecimals decimals of ERC4626 token
    /// @param oracle vault shares price oracle
    function addVault(
        uint32 chainId,
        uint256 superformId,
        address vault,
        uint8 vaultDecimals,
        ISharePriceOracle oracle
    )
        external
        onlyRoles(MANAGER_ROLE)
    {
        if (superformId == 0) revert InvalidSuperformId();
        // If its already listed revert
        if (isVaultListed(vault)) revert VaultAlreadyListed();

        // Save it into storage
        vaults[superformId].chainId = chainId;
        vaults[superformId].superformId = superformId;
        vaults[superformId].vaultAddress = vault;
        vaults[superformId].decimals = vaultDecimals;
        vaults[superformId].oracle = oracle;
        uint192 lastSharePrice = vaults[superformId].sharePrice(asset()).toUint192();
        if (lastSharePrice == 0) revert();
        _vaultToSuperformId[vault] = superformId;

        bool found;

        if (chainId == THIS_CHAIN_ID) {
            // Push it to the local withdrawal queue
            uint256[WITHDRAWAL_QUEUE_SIZE] memory queue = localWithdrawalQueue;
            for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE; i++) {
                if (queue[i] == 0) {
                    localWithdrawalQueue[i] = superformId;
                    found = true;
                    break;
                }
            }
            // If its on the same chain perfom approval to vault
            asset().safeApprove(vault, type(uint256).max);
        } else {
            // Push it to the crosschain withdrawal queue
            uint256[WITHDRAWAL_QUEUE_SIZE] memory queue = xChainWithdrawalQueue;
            for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE; i++) {
                if (queue[i] == 0) {
                    xChainWithdrawalQueue[i] = superformId;
                    found = true;
                    break;
                }
            }
        }
        if (!found) revert MaxQueueSizeExceeded();

        emit AddVault(chainId, vault);
    }

    /// @notice Remove a vault from the portfolio
    /// @param superformId id of vault to be removed
    function removeVault(uint256 superformId) external onlyRoles(MANAGER_ROLE) {
        if (superformId == 0) revert InvalidSuperformId();

        VaultData memory vault = vaults[superformId];

        if (vault.convertToAssets(_sharesBalance(vaults[superformId]), asset(), true) > dustThreshold) {
            revert SharesBalanceNotZero();
        }

        uint64 chainId = vault.chainId;
        address vaultAddress = vault.vaultAddress;
        delete vaults[superformId];
        delete _vaultToSuperformId[vaultAddress];
        if (chainId == THIS_CHAIN_ID) {
            // Remove vault from the local withdrawal queue
            uint256[WITHDRAWAL_QUEUE_SIZE] memory queue = localWithdrawalQueue;
            for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE; i++) {
                if (queue[i] == superformId) {
                    localWithdrawalQueue[i] = 0;
                    _organizeWithdrawalQueue(localWithdrawalQueue);
                    break;
                }
            }
            // If its on the same chain revoke approval to vault
            asset().safeApprove(vaultAddress, 0);
        } else {
            // Remove vault from the crosschain withdrawal queue
            uint256[WITHDRAWAL_QUEUE_SIZE] memory queue = xChainWithdrawalQueue;
            for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE; i++) {
                if (queue[i] == superformId) {
                    xChainWithdrawalQueue[i] = 0;
                    _organizeWithdrawalQueue(xChainWithdrawalQueue);
                    break;
                }
            }
        }
        emit RemoveVault(chainId, vaultAddress);
    }

    /// @notice Rearranges the withdrawal queue order
    /// @param queueType 0 for local queue, 1 for cross-chain queue
    /// @param newOrder Array of superformIds in desired order
    /// @dev Only callable by MANAGER_ROLE
    /// @dev Maintains same vaults but in different order
    function rearrangeWithdrawalQueue(
        uint8 queueType,
        uint256[WITHDRAWAL_QUEUE_SIZE] calldata newOrder
    )
        external
        onlyRoles(MANAGER_ROLE)
    {
        // Select queue based on type
        uint256[WITHDRAWAL_QUEUE_SIZE] storage queue;
        if (queueType == 0) {
            queue = localWithdrawalQueue;
        } else if (queueType == 1) {
            queue = xChainWithdrawalQueue;
        } else {
            revert InvalidQueueType();
        }

        // Create temporary arrays for validation
        uint256[] memory currentVaults = new uint256[](WITHDRAWAL_QUEUE_SIZE);
        uint256[] memory newVaults = new uint256[](WITHDRAWAL_QUEUE_SIZE);
        uint256 currentCount;
        uint256 newCount;

        // Collect non-zero vaults from current queue
        for (uint256 i = 0; i < WITHDRAWAL_QUEUE_SIZE; i++) {
            if (queue[i] != 0) {
                currentVaults[currentCount++] = queue[i];
            }
        }

        // Collect non-zero vaults from new order
        for (uint256 i = 0; i < WITHDRAWAL_QUEUE_SIZE; i++) {
            if (newOrder[i] != 0) {
                // Check for duplicates
                for (uint256 j = 0; j < newCount; j++) {
                    if (newVaults[j] == newOrder[i]) revert DuplicateVaultInOrder();
                }
                newVaults[newCount++] = newOrder[i];
            }
        }

        // Verify same number of non-zero vaults
        if (currentCount != newCount) revert VaultCountMismatch();

        // Verify all current vaults are in new order
        for (uint256 i = 0; i < currentCount; i++) {
            bool found = false;
            for (uint256 j = 0; j < newCount; j++) {
                if (currentVaults[i] == newVaults[j]) {
                    found = true;
                    break;
                }
            }
            if (!found) revert MissingVaultFromCurrentQueue();
        }

        // Update queue with new order
        for (uint256 i = 0; i < WITHDRAWAL_QUEUE_SIZE; i++) {
            queue[i] = newOrder[i];
        }
    }

    /// @notice Reorganize `withdrawalQueue` based on premise that if there is an
    /// empty value between two actual values, then the empty value should be
    /// replaced by the later value.
    /// @dev Relative ordering of non-zero values is maintained.
    function _organizeWithdrawalQueue(uint256[WITHDRAWAL_QUEUE_SIZE] storage queue) internal {
        uint256 offset;
        for (uint256 i; i < WITHDRAWAL_QUEUE_SIZE;) {
            uint256 vault = queue[i];
            if (vault == 0) {
                unchecked {
                    ++offset;
                }
            } else if (offset > 0) {
                queue[i - offset] = vault;
                queue[i] = 0;
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Allows direct donation of assets to the vault
    /// @dev Transfers assets from sender to vault and updates idle balance
    /// @param assets The amount of assets to donate
    function donate(uint256 assets) external {
        asset().safeTransferFrom(msg.sender, address(this), assets);
        _afterDeposit(assets, 0);
    }

    /// @notice the number of decimals of the underlying token
    function _underlyingDecimals() internal view override returns (uint8) {
        return _decimals;
    }

    /// @notice Updates the average entry share price of a controller
    function _updatePosition(address controller, uint256 mintedShares) internal {
        uint256 averageEntryPrice = positions[controller];
        uint256 currentSharePrice = sharePrice();
        uint256 sharesBalance = balanceOf(controller);
        if (averageEntryPrice == 0 || sharesBalance == 0) {
            positions[controller] = currentSharePrice;
        } else {
            uint256 totalCost = sharesBalance * averageEntryPrice + mintedShares * currentSharePrice;
            uint256 newTotalAmount = sharesBalance + mintedShares;
            uint256 newAverageEntryPrice = totalCost / newTotalAmount;
            positions[controller] = newAverageEntryPrice;
        }
    }

    /// @dev Hook that is called after any deposit or mint.
    function _afterDeposit(uint256 assets, uint256 /*uint shares*/ ) internal override {
        uint128 assetsUint128 = assets.toUint128();
        _totalIdle += assetsUint128;
    }

    /// @dev Reverts if deposited shares are locked
    /// @param controller shares controller
    function _checkSharesLocked(address controller) private view {
        if (block.timestamp < _depositLockCheckPoint[controller] + sharesLockTime) revert SharesLocked();
    }

    /// @dev Locks the deposited shares for a fixed period
    /// @param controller shares receiver
    /// @param sharesBalance current shares balance
    /// @param newShares newly minted shares
    function _lockShares(address controller, uint256 sharesBalance, uint256 newShares) private {
        uint256 newBalance = sharesBalance + newShares;
        if (sharesBalance == 0) {
            _depositLockCheckPoint[controller] = block.timestamp;
        } else {
            _depositLockCheckPoint[controller] = ((_depositLockCheckPoint[controller] * sharesBalance) / newBalance)
                + ((block.timestamp * newShares) / newBalance);
        }
    }

    /// @dev Supports ERC1155 interface detection
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @return isSupported True if the contract supports the interface, false otherwise
    function supportsInterface(bytes4 interfaceId) public pure returns (bool isSupported) {
        if (interfaceId == 0x4e2312e0) return true;
    }

    /// @dev
    function convertToSuperPositions(uint256 superformId, uint256 assets) external view returns (uint256) {
        return vaults[superformId].convertToShares(assets, asset(), false);
    }

    /// @notice Handles the receipt of a single ERC1155 token type
    /// @dev This function is called at the end of a `safeTransferFrom` after the balance has been updated
    /// @param operator The address which initiated the transfer (i.e. msg.sender)
    /// @param from The address which previously owned the token
    /// @param superformId The ID of the token being transferred
    /// @param value The amount of tokens being transferred
    /// @param data Additional data with no specified format
    /// @return bytes4 `bytes4(keccak256("onERC1155Received(address,address,uint,uint,bytes)"))`
    function onERC1155Received(
        address operator,
        address from,
        uint256 superformId,
        uint256 value,
        bytes memory data
    )
        public
        returns (bytes4)
    {
        // Silence compiler warnings
        operator;
        value;
        if (msg.sender != address(gateway.superPositions())) revert Unauthorized();
        if (from != address(gateway)) revert Unauthorized();
        if (data.length > 0) {
            (address controller, uint256 refundedAssets) = abi.decode(data, (address, uint256));
            if (refundedAssets != 0) {
                _totalDebt += refundedAssets.toUint128();
                // Calculate shares corresponding to refundedAssets
                uint256 shares = _convertToShares(refundedAssets, totalAssets() - refundedAssets);
                if (controller != address(0)) {
                    // Decrease the pending xchain shares of the user
                    pendingProcessedShares[controller] = _sub0(pendingProcessedShares[controller], shares);
                }
                vaults[superformId].totalDebt += refundedAssets.toUint128();
                // Mint back failed shares
                _mint(address(this), shares);
            }
        }
        return this.onERC1155Received.selector;
    }

    /// @notice Handles the receipt of multiple ERC1155 token types
    /// @dev This function is called at the end of a `safeBatchTransferFrom` after the balances have been updated
    /// @param operator The address which initiated the batch transfer (i.e. msg.sender)
    /// @param from The address which previously owned the tokens
    /// @param superformIds An array containing ids of each token being transferred (order and length must match values
    /// array)
    /// @param values An array containing amounts of each token being transferred (order and length must match ids
    /// array)
    /// @param data Additional data with no specified format
    /// @return bytes4 `bytes4(keccak256("onERC1155BatchReceived(address,address,uint[],uint[],bytes)"))`
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] memory superformIds,
        uint256[] memory values,
        bytes memory data
    )
        public
        returns (bytes4)
    {
        // Silence compiler warnings
        operator;
        values;
        data;
        superformIds;
        if (msg.sender != address(gateway.superPositions())) revert Unauthorized();
        if (from != address(gateway)) revert Unauthorized();
        return this.onERC1155BatchReceived.selector;
    }
}
