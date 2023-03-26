// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.17;
import "hardhat/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IConnext} from "@connext/smart-contracts/contracts/core/connext/interfaces/IConnext.sol";
import {IXReceiver} from "@connext/smart-contracts/contracts/core/connext/interfaces/IXReceiver.sol";

import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import {ISuperfluid, ISuperToken, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/OpsTaskCreator.sol";
import {IDestinationPool} from "../interfaces/IDestinationPool.sol";

error Unauthorized();
error InvalidAgreement();
error InvalidToken();
error StreamAlreadyActive();

/// @title Origin Pool to Receive Streams.
/// @notice This is a super app. On stream (create|update|delete), this contract sends a message
/// accross the bridge to the DestinationPool.

contract XStreamPool is SuperAppBase, IXReceiver, OpsTaskCreator {
    /// @dev Emitted when flow message is sent across the bridge.
    /// @param flowRate Flow Rate, unadjusted to the pool.
    event FlowStartMessage(
        address indexed sender,
        address indexed receiver,
        int96 flowRate,
        uint256 startTime
    );
    event FlowTopupMessage(
        address indexed sender,
        address indexed receiver,
        int96 newFlowRate,
        uint256 topupTime,
        uint256 endTime
    );
    event FlowEndMessage(
        address indexed sender,
        address indexed receiver,
        int96 flowRate
    );

    event XStreamFlowTrigger(
        address indexed sender,
        address indexed receiver,
        address indexed selectedToken,
        int96 flowRate,
        uint256 amount,
        uint256 streamStatus,
        uint256 startTime,
        uint256 bufferFee,
        uint256 networkFee,
        uint32 destinationDomain
    );

    enum StreamOptions {
        START,
        TOPUP,
        END
    }

    /// @dev Emitted when rebalance message is sent across the bridge.
    /// @param amount Amount rebalanced (sent).
    event RebalanceMessageSent(uint256 amount);

    //TODO  /// @dev Connext contracts GNOSIS.
    IConnext public immutable connext =
        IConnext(0x5bB83e95f63217CDa6aE3D181BA580Ef377D2109);

    /// @dev Superfluid contracts.
    ISuperfluid public immutable host =
        ISuperfluid(0x2dFe937cD98Ab92e59cF3139138f18c823a4efE7);
    IConstantFlowAgreementV1 public immutable cfa =
        IConstantFlowAgreementV1(0xEbdA4ceF883A7B12c4E669Ebc58927FBa8447C7D);
    ISuperToken public immutable superToken =
        ISuperToken(0x1234756ccf0660E866305289267211823Ae86eEc);
    IERC20 public erc20Token =
        IERC20(0xDDAfbb505ad214D7b80b1f830fcCc89B60fb7A83);

    // TODO  /// @dev Connext contracts POLYGON.
    // IConnext public immutable connext =
    //     IConnext(0x11984dc4465481512eb5b777E44061C158CF2259);

    // /// @dev Superfluid contracts.
    // ISuperfluid public immutable host =
    //     ISuperfluid(0x3E14dC1b13c488a8d5D310918780c983bD5982E7);
    // IConstantFlowAgreementV1 public immutable cfa =
    //     IConstantFlowAgreementV1(0x6EeE6060f715257b970700bc2656De21dEdF074C);
    // ISuperToken public immutable superToken =
    //     ISuperToken(0xCAa7349CEA390F89641fe306D93591f87595dc1F);
    // IERC20 public erc20Token =
    //     IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);

    // TODO /// @dev Connext contracts MUMBAI.
    // IConnext public immutable connext =
    //     IConnext(0x2334937846Ab2A3FCE747b32587e1A1A2f6EEC5a);

    // /// @dev Superfluid contracts.
    // ISuperfluid public immutable host =
    //     ISuperfluid(0xEB796bdb90fFA0f28255275e16936D25d3418603);
    // IConstantFlowAgreementV1 public immutable cfa =
    //     IConstantFlowAgreementV1(0x49e565Ed1bdc17F3d220f72DF0857C26FA83F873);
    // ISuperToken public immutable superToken =
    //     ISuperToken(0xFB5fbd3B9c471c1109A3e0AD67BfD00eE007f70A);
    // IERC20 public erc20Token =
    //     IERC20(0xeDb95D8037f769B72AAab41deeC92903A98C9E16);

    // TODO /// @dev Connext contracts GOERLI.
    // IConnext public immutable connext =
    //     IConnext(0xFCa08024A6D4bCc87275b1E4A1E22B71fAD7f649);

    // /// @dev Superfluid contracts.
    // ISuperfluid public immutable host =
    //     ISuperfluid(0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9);
    // IConstantFlowAgreementV1 public immutable cfa =
    //     IConstantFlowAgreementV1(0xEd6BcbF6907D4feEEe8a8875543249bEa9D308E8);
    // ISuperToken public immutable superToken =
    //     ISuperToken(0x3427910EBBdABAD8e02823DFe05D34a65564b1a0);
    // IERC20 public erc20Token =
    //     IERC20(0x7ea6eA49B0b0Ae9c5db7907d139D9Cd3439862a1);

    /// @dev Validates callbacks.
    /// @param _agreementClass MUST be CFA.
    /// @param _token MUST be supported token.
    modifier isCallbackValid(address _agreementClass, ISuperToken _token) {
        if (msg.sender != address(host)) revert Unauthorized();
        if (_agreementClass != address(cfa)) revert InvalidAgreement();
        if (_token != superToken) revert InvalidToken();
        _;
    }

    ///TODO  @dev Gelato OPs Contract POLYGON
    // address payable _ops = payable(0x527a819db1eb0e34426297b03bae11F2f8B3A19E);

    ///TODO  @dev Gelato OPs Contract GNOSIS
    address payable _ops = payable(0x8aB6aDbC1fec4F18617C9B889F5cE7F28401B8dB);

    ///TODO  @dev Gelato OPs Contract MUMBAI
    // address payable _ops = payable(0xB3f5503f93d5Ef84b06993a1975B9D21B962892F);

    // /// @dev Gelato OPs Contract GOERLI
    // address payable _ops = payable(0xc1C6805B857Bef1f412519C4A842522431aFed39);

    constructor() OpsTaskCreator(_ops, msg.sender) {
        // surely this can't go wrong
        IERC20(superToken.getUnderlyingToken()).approve(
            address(connext),
            type(uint256).max
        );

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
    function rebalance(
        uint32 destinationDomain,
        address destinationContract
    ) external {
        _sendRebalanceMessage(destinationDomain, destinationContract);
    }

    function deleteStream(address account) external {
        bytes memory _callData = abi.encodeCall(
            cfa.deleteFlow,
            (superToken, address(this), account, new bytes(0))
        );

        host.callAgreement(cfa, _callData, new bytes(0));

        (uint256 fee, address feeToken) = _getFeeDetails();
        _transfer(fee, feeToken);
    }

    function createTask(
        address _user,
        uint256 _interval,
        uint256 _startTime
    ) internal returns (bytes32) {
        bytes memory execData = abi.encodeWithSelector(
            this.deleteStream.selector,
            _user
        );

        ModuleData memory moduleData = ModuleData({
            modules: new Module[](3),
            args: new bytes[](3)
        });

        moduleData.modules[0] = Module.TIME;
        moduleData.modules[1] = Module.PROXY;
        moduleData.modules[2] = Module.SINGLE_EXEC;

        moduleData.args[0] = _timeModuleArg(_startTime, _interval);
        moduleData.args[1] = _proxyModuleArg();
        moduleData.args[2] = _singleExecModuleArg();

        bytes32 id = _createTask(address(this), execData, moduleData, ETH);
        return id;
    }

    // for streamActionType: 1 -> start stream, 2 -> Topup stream, 3 -> delete stream
    function _sendFlowMessage(
        uint256 _streamActionType,
        address _receiver,
        int96 _flowRate,
        uint256 relayerFee, // currently hardcoded
        uint256 slippage,
        uint256 cost,
        address bridgingToken,
        address destinationContract,
        uint32 destinationDomain
    ) public payable {
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
            _streamActionType,
            msg.sender,
            _receiver,
            _flowRate,
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
        emit XStreamFlowTrigger(
            msg.sender,
            _receiver,
            address(bridgingToken),
            _flowRate,
            cost,
            1,
            block.timestamp,
            0,
            relayerFee,
            destinationDomain
        );
    }

    function _sendToManyFlowMessage(
        address[] calldata receivers,
        int96[] calldata flowRates,
        uint96[] memory costs,
        uint256 _streamActionType,
        // address receiver,
        // int96 flowRate,
        uint256 relayerFee,
        uint256 slippage,
        // uint256 cost,
        address bridgingToken,
        address destinationContract,
        uint32 destinationDomain
    ) external payable {
        for (uint256 i = 0; i < receivers.length; i++) {
            _sendFlowMessage(
                _streamActionType,
                receivers[i],
                flowRates[i],
                relayerFee,
                slippage,
                costs[i],
                bridgingToken,
                destinationContract,
                destinationDomain
            );
        }
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

    event StreamStart(
        address indexed sender,
        address receiver,
        int96 flowRate,
        uint256 startTime
    );
    event StreamUpdate(
        address indexed sender,
        address indexed receiver,
        int96 flowRate,
        uint256 startTime
    );
    event StreamDelete(address indexed sender, address indexed receiver);
    event XReceiveData(
        address indexed originSender,
        uint32 origin,
        address asset,
        uint256 amount,
        bytes32 transferId,
        uint256 receiveTimestamp,
        address senderAccount,
        address receiverAccount,
        int256 flowRate
    );

    // receive functions

    /// @dev Virtual "flow rate" of fees being accrued in real time.
    int96 public feeAccrualRate;
    /// @dev Last update's timestamp of the `feeAccrualRate`.
    uint256 public lastFeeAccrualUpdate;
    /// @dev Fees pending that are NOT included in the `feeAccrualRate`
    //   TODO this might not be necessary since the full balance is sent on flow update.
    uint256 public feesPending;

    function _updateFeeFlowRate(int96 feeFlowRate) internal {
        feesPending = 0;
        feeAccrualRate += feeFlowRate;
        lastFeeAccrualUpdate = block.timestamp;
    }

    function receiveFlowMessage(
        address _account,
        int96 _flowRate,
        uint256 _amount,
        uint256 _startTime // override
    ) public {
        // 0.1%
        int96 feeFlowRate = (_flowRate * 10) / 10000;

        // update fee accrual rate
        _updateFeeFlowRate(feeFlowRate);

        // Adjust for fee on the destination for fee computation.
        int96 flowRateAdjusted = _flowRate - feeFlowRate;

        // if possible, upgrade all non-super tokens in the pool
        // uint256 balance = IERC20(token.getUnderlyingToken()).balanceOf(address(this));

        // if (balance > 0) token.upgrade(balance);

        (, int96 existingFlowRate, , ) = cfa.getFlow(
            superToken,
            address(this),
            _account
        );

        bytes memory callData;

        if (existingFlowRate == 0) {
            if (flowRateAdjusted == 0) return; // do not revert
            // create
            callData = abi.encodeCall(
                cfa.createFlow,
                (superToken, _account, flowRateAdjusted, new bytes(0))
            );
        } else if (flowRateAdjusted > 0) {
            // update
            callData = abi.encodeCall(
                cfa.updateFlow,
                (superToken, _account, flowRateAdjusted, new bytes(0))
            );
        } else {
            // delete
            callData = abi.encodeCall(
                cfa.deleteFlow,
                (superToken, address(this), _account, new bytes(0))
            );
        }

        host.callAgreement(cfa, callData, new bytes(0));

        /// @dev Gelato OPS is called here
        if (existingFlowRate == 0) {
            if (flowRateAdjusted == 0) return; // do not revert
            // create task
            uint256 _interval = _amount / uint256(uint96(flowRateAdjusted));
            // uint256 _interval = 100;
            createTask(_account, _interval, _startTime);
        }

        // emit FlowMessageReceived(account, flowRateAdjusted);
    }

    function xReceive(
        bytes32 _transferId,
        uint256 _amount,
        address _asset,
        address _originSender,
        uint32 _origin,
        bytes memory _callData
    ) external returns (bytes memory) {
        // Unpack the _callData

        (streamActionType, sender, receiver, flowRate, startTime) = abi.decode(
            _callData,
            (uint256, address, address, int96, uint256)
        );
        amount = _amount;
        emit XReceiveData(
            _originSender,
            _origin,
            _asset,
            _amount,
            _transferId,
            block.timestamp,
            sender,
            receiver,
            flowRate
        );
        approveSuperToken(address(_asset), _amount);
        receiveFlowMessage(receiver, flowRate, _amount, startTime);

        if (streamActionType == 1) {
            emit StreamStart(msg.sender, receiver, flowRate, startTime);
        } else if (streamActionType == 2) {
            emit StreamUpdate(sender, receiver, flowRate, startTime);
        } else {
            emit StreamDelete(sender, receiver);
        }
        // receiveFlowMessage(receiver, flowRate);
    }

    event UpgradeToken(address indexed baseToken, uint256 amount);

    function approveSuperToken(address _asset, uint256 _amount) public {
        IERC20(_asset).approve(address(superToken), _amount); // approving the superToken contract to upgrade TEST
        ISuperToken(address(superToken)).upgrade(_amount);
        emit UpgradeToken(_asset, _amount);
    }
}
