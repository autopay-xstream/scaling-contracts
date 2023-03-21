// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.17;
import "hardhat/console.sol";

import {IDestinationPool} from "../interfaces/IDestinationPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IConnext} from "@connext/smart-contracts/contracts/core/connext/interfaces/IConnext.sol";
import {IXReceiver} from "@connext/smart-contracts/contracts/core/connext/interfaces/IXReceiver.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import {ISuperfluid, ISuperToken, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error Unauthorized();
error InvalidAgreement();
error InvalidToken();
error StreamAlreadyActive();

/// @title Origin Pool to Receive Streams.
/// @notice This is a super app. On stream (create|update|delete), this contract sends a message
/// accross the bridge to the DestinationPool.

contract OriginPool is SuperAppBase, IXReceiver {
    // contract events
    event xStreamFlowTrigger(
        address indexed sender,
        address indexed receiver,
        address indexed selectedToken,
        int96 flowRate,
        uint256 streamStatus,
        uint256 startTime,
        uint256 bufferFee,
        uint256 networkFee,
        uint32 destinationDomain
    );
    event RebalanceMessageSent(uint256 amount);
    event updatingPing(address sender, uint256 pingCount);
    event StreamStart(
        address indexed sender,
        address indexed receiver,
        address indexed tokenAddress,
        int96 flowRate,
        uint256 tokenAmount
    );
    event StreamUpdate(
        address indexed sender,
        address indexed receiver,
        address indexed tokenAddress,
        int96 flowRate,
        uint256 tokenAmount
    );
    event StreamDelete(
        address indexed sender,
        address indexed receiver,
        address indexed tokenAddress,
        int96 flowRate,
        uint256 tokenAmount
    );
    event UpgradeToken(address indexed baseToken, uint256 amount);

    /// @dev Emitted when rebalance message is sent across the bridge.
    /// @param amount Amount rebalanced (sent).

    /// @dev Connext contracts.
    IConnext public immutable connext =
        IConnext(0xFCa08024A6D4bCc87275b1E4A1E22B71fAD7f649);
    /// @dev Superfluid contracts.
    ISuperfluid public immutable host =
        ISuperfluid(0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9);
    IConstantFlowAgreementV1 public immutable cfa =
        IConstantFlowAgreementV1(0xEd6BcbF6907D4feEEe8a8875543249bEa9D308E8);
    ISuperToken public immutable superToken =
        ISuperToken(0x3427910EBBdABAD8e02823DFe05D34a65564b1a0); // TESTx on goerli
    IERC20 public erc20Token =
        IERC20(0x7ea6eA49B0b0Ae9c5db7907d139D9Cd3439862a1); // TEST on goerli

    /// @dev Validates callbacks.
    /// @param _agreementClass MUST be CFA.
    /// @param _token MUST be supported token.
    modifier isCallbackValid(address _agreementClass, ISuperToken _token) {
        if (msg.sender != address(host)) revert Unauthorized();
        if (_agreementClass != address(cfa)) revert InvalidAgreement();
        if (_token != superToken) revert InvalidToken();
        _;
    }

    constructor() {
        // surely this can't go wrong
        IERC20(erc20Token).approve(address(connext), type(uint256).max);

        // register app
        host.registerApp(
            SuperAppDefinitions.APP_LEVEL_FINAL |
                SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
                SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
                SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP
        );
        console.log("Address performing the approval", msg.sender);
    }

    receive() external payable {}

    fallback() external payable {}

    /// @dev Rebalances pools. This sends funds over the bridge to the destination.
    function rebalance(uint32 destinationDomain, address destinationContract)
        external
    {
        _sendRebalanceMessage(destinationDomain, destinationContract);
    }

    // for streamActionType: 1 -> start stream, 2 -> Topup stream, 3 -> delete stream
    function _sendFlowMessage(
        uint256 streamActionType,
        address receiver,
        int96 flowRate,
        uint256 relayerFee, // currently hardcoded
        uint256 slippage,
        uint256 cost,
        address bridgingToken,
        address destinationContract,
        uint32 destinationDomain
    ) external payable {
        if (bridgingToken == address(superToken)) {
            // if user is sending Super Tokens
            ISuperToken(superToken).approve(address(this), type(uint256).max);
            superToken.transferFrom(msg.sender, address(this), cost); // here the sender is my wallet account, cost is the amount of TEST or TESTx tokens
            // supertokens won't be bridged, just the callData
        } else if (bridgingToken == address(erc20Token)) {
            // if user is sending ERC20 tokens
            IERC20(superToken.getUnderlyingToken()).approve(
                address(this),
                type(uint256).max
            );
            erc20Token.transferFrom(msg.sender, address(this), cost); // here the sender is my wallet account, cost is the amount of TEST or TESTx tokens
            erc20Token.approve(address(connext), cost); // approve the connext contracts to handle OriginPool's liquidity
        } else {
            revert("Send the correct token to bridge");
        }

        bytes memory callData = abi.encode(
            streamActionType,
            msg.sender,
            receiver,
            flowRate,
            block.timestamp
        );
        connext.xcall{value: relayerFee}(
            destinationDomain, // _destination: Domain ID of the destination chain
            destinationContract, // _to: contract address receiving the funds on the destination chain
            address(bridgingToken), // _asset: address of the token contract
            msg.sender, // _delegate: address that can revert or forceLocal on destination
            cost, // _amount: amount of tokens to transfer, // 0 if just sending a message
            slippage, // _slippage: the maximum amount of slippage the user will accept in BPS
            callData // _callData
        );
        emit xStreamFlowTrigger(
            msg.sender,
            receiver,
            address(bridgingToken),
            flowRate,
            1,
            block.timestamp,
            0,
            relayerFee,
            destinationDomain
        );
    }

    /// @dev Sends rebalance message with the full balance of this pool. No need to collect dust.
    function _sendRebalanceMessage(
        uint32 destinationDomain,
        address destinationContract
    ) internal {
        uint256 balance = superToken.balanceOf(address(this));
        // downgrade for sending across the bridge
        superToken.downgrade(balance);
        // encode call
        bytes memory callData = abi.encodeWithSelector(
            IDestinationPool.receiveRebalanceMessage.selector
        );
        uint256 relayerFee = 0;
        uint256 slippage = 0;
        connext.xcall{value: relayerFee}(
            destinationDomain, // _destination: Domain ID of the destination chain
            destinationContract, // _to: contract address receiving the funds on the destination chain
            superToken.getUnderlyingToken(), // _asset: address of the token contract
            address(this), // _delegate: address that can revert or forceLocal on destination
            balance, // _amount: amount of tokens to transfer
            slippage, // _slippage: the maximum amount of slippage the user will accept in BPS
            callData // _callData
        );
        emit RebalanceMessageSent(balance);
    }

    /////////////////////////////////////////////////// Current Contract as DestinationPool //////////////////////////////////////

    uint256 public streamActionType; // 1 -> Start stream, 2 -> Topup stream, 3 -> Delete stream
    address public sender;
    address public receiver;
    int96 public flowRate;
    uint256 public startTime;
    uint256 public amount;
    uint256 public testIncrement;

    // receive functions

    /// @dev Virtual "flow rate" of fees being accrued in real time.
    int96 public feeAccrualRate;
    /// @dev Last update's timestamp of the `feeAccrualRate`.
    uint256 public lastFeeAccrualUpdate;
    /// @dev Fees pending that are NOT included in the `feeAccrualRate`
    // TODO this might not be necessary since the full balance is sent on flow update.
    uint256 public feesPending;

    function _updateFeeFlowRate(int96 feeFlowRate) internal {
        feesPending = 0;
        feeAccrualRate += feeFlowRate;
        lastFeeAccrualUpdate = block.timestamp;
    }

    function receiveFlowMessage(address account, int96 flowRate) public {
        // 0.1%
        int96 feeFlowRate = (flowRate * 10) / 10000;
        // update fee accrual rate
        _updateFeeFlowRate(feeFlowRate);
        // Adjust for fee on the destination for fee computation.
        int96 flowRateAdjusted = flowRate - feeFlowRate;
        (, int96 existingFlowRate, , ) = cfa.getFlow(
            superToken,
            address(this),
            account
        );
        bytes memory callData;
        if (existingFlowRate == 0) {
            if (flowRateAdjusted == 0) return; // do not revert
            // create
            callData = abi.encodeCall(
                cfa.createFlow,
                (superToken, account, flowRateAdjusted, new bytes(0))
            );
        } else if (flowRateAdjusted > 0) {
            // update
            callData = abi.encodeCall(
                cfa.updateFlow,
                (superToken, account, flowRateAdjusted, new bytes(0))
            );
        } else {
            // delete
            callData = abi.encodeCall(
                cfa.deleteFlow,
                (superToken, address(this), account, new bytes(0))
            );
        }
        host.callAgreement(cfa, callData, new bytes(0));
    }

    function xReceive(
        bytes32 _transferId,
        uint256 _amount,
        address _asset,
        address _originSender,
        uint32 _origin,
        bytes memory _callData
    ) external returns (bytes memory) {
        (streamActionType, sender, receiver, flowRate, startTime) = abi.decode(
            _callData,
            (uint256, address, address, int96, uint256)
        );
        amount = _amount;
        approveSuperToken(address(_asset), _amount);
        receiveFlowMessage(receiver, flowRate);

        if (streamActionType == 1) {
            emit StreamStart(sender, receiver, _asset, flowRate, _amount);
        } else if (streamActionType == 2) {
            emit StreamUpdate(sender, receiver, _asset, flowRate, _amount);
        } else {
            emit StreamDelete(sender, receiver, _asset, int96(0), uint256(0));
        }
    }

    function approveSuperToken(address _asset, uint256 _amount) public {
        IERC20(_asset).approve(address(superToken), _amount); // approving the superToken contract to upgrade TEST
        ISuperToken(address(superToken)).upgrade(_amount);
        emit UpgradeToken(_asset, _amount);
    }
}
