// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.17;
import "hardhat/console.sol";

import {IConnext} from "@connext/smart-contracts/contracts/core/connext/interfaces/IConnext.sol";
import {IXReceiver} from "@connext/smart-contracts/contracts/core/connext/interfaces/IXReceiver.sol";

import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import {ISuperfluid, ISuperToken, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {IDestinationPool} from "../interfaces/IDestinationPool.sol";

import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import "../interfaces/OpsTaskCreator.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error Unauthorized();
error InvalidDomain();
error InvalidOriginContract();

contract DestinationPool is
    IXReceiver,
    AutomationCompatibleInterface,
    IDestinationPool,
    OpsTaskCreator
{
    using SuperTokenV1Library for ISuperToken;

    // contract events
    event RebalanceMessageReceived();
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

    /// @dev Gelato OPs Contract
    address payable _ops = payable(0xB3f5503f93d5Ef84b06993a1975B9D21B962892F); // address for Mumbai

    constructor() OpsTaskCreator(_ops, msg.sender) {}

    /// @dev Emitted when connext delivers a rebalance message. // TODO Add amount?

    /// @dev Connext contracts.
    IConnext public immutable connext =
        IConnext(0x2334937846Ab2A3FCE747b32587e1A1A2f6EEC5a); // Connext address on Polygon Mainnet
    /// @dev Superfluid contracts.
    ISuperfluid public immutable host =
        ISuperfluid(0xEB796bdb90fFA0f28255275e16936D25d3418603);
    IConstantFlowAgreementV1 public immutable cfa =
        IConstantFlowAgreementV1(0x49e565Ed1bdc17F3d220f72DF0857C26FA83F873);
    ISuperToken public immutable superToken =
        ISuperToken(0xFB5fbd3B9c471c1109A3e0AD67BfD00eE007f70A); // TESTx on Mumbai
    IERC20 public erc20Token =
        IERC20(0xeDb95D8037f769B72AAab41deeC92903A98C9E16); // TEST token on Mumbai

    /// @dev Virtual "flow rate" of fees being accrued in real time.
    int96 public feeAccrualRate;

    /// @dev Last update's timestamp of the `feeAccrualRate`.
    uint256 public lastFeeAccrualUpdate;

    /// @dev Fees pending that are NOT included in the `feeAccrualRate`
    // TODO this might not be necessary since the full balance is sent on flow update.
    uint256 public feesPending;

    /// @dev Validates message sender, origin, and originContract.
    modifier onlySource(
        address _originSender,
        address originContract,
        uint32 _origin,
        uint32 originDomain
    ) {
        require(
            _origin == originDomain &&
                _originSender == originContract &&
                msg.sender == address(connext),
            "Expected source contract on origin domain called by Connext"
        );
        _;
    }

    receive() external payable {}

    fallback() external payable {}

    // //////////////////////////////////////////////////////////////
    // MESSAGE RECEIVERS
    // //////////////////////////////////////////////////////////////
    uint256 lastTimeStamp;
    uint256 interval;

    // stream variables
    uint256 public streamActionType; // 1 -> Start stream, 2 -> Topup stream, 3 -> Delete stream
    address public sender;
    address public receiver;
    int96 public flowRate;
    uint256 public startTime;
    uint256 public amount;
    uint256 public testIncrement;

    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        // upkeepNeeded = (block.timestamp - lastTimeStamp) > interval;
        upkeepNeeded = streamActionType == 1;
        // We don't use the checkData in this example. The checkData is defined when the Upkeep was registered.
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
        uint256 startTime
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

        moduleData.args[0] = _timeModuleArg(startTime, _interval);
        moduleData.args[1] = _proxyModuleArg();
        moduleData.args[2] = _singleExecModuleArg();

        bytes32 id = _createTask(address(this), execData, moduleData, ETH);
        return id;
    }

    function performUpkeep(
        bytes calldata /* performData */
    ) external override {
        //We highly recommend revalidating the upkeep in the performUpkeep function
        // if ((block.timestamp - lastTimeStamp) > interval) {

        // }
        // IERC20(token.getUnderlyingToken()).approve(address(token), amount); //approving the upgradation
        // ISuperToken(address(token)).upgrade(amount); // upgrading
        testIncrement = testIncrement + 1;
        streamActionType = 0;

        // We don't use the performData in this example. The performData is generated by the Automation Node's call to your checkUpkeep function
    }

    string public callData;
    uint256 public ping = 0;

    function receiveFlowMessage(
        address account,
        int96 flowRate,
        uint256 amount,
        uint256 startTime
    ) public override {
        // 0.1%
        int96 feeFlowRate = (flowRate * 10) / 10000;

        // update fee accrual rate
        _updateFeeFlowRate(feeFlowRate);

        // Adjust for fee on the destination for fee computation.
        int96 flowRateAdjusted = flowRate - feeFlowRate;

        // if possible, upgrade all non-super tokens in the pool
        // uint256 balance = IERC20(token.getUnderlyingToken()).balanceOf(address(this));

        // if (balance > 0) token.upgrade(balance);

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

        /// @dev Gelato OPS is called here
        if (existingFlowRate == 0) {
            if (flowRateAdjusted == 0) return; // do not revert
            // create task
            // uint256 _interval = amount / flowRateAdjusted;      @dev TODO
            uint256 _interval = 100;
            createTask(account, _interval, startTime);
        }
    }

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
            // supertokens will not be bridged, only callData will
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

        console.log("Received calldata ", callData);

        approveSuperToken(address(_asset), _amount);
        updatePing(_originSender);

        receiveFlowMessage(receiver, flowRate, _amount, startTime);

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

    function updatePing(address sender) public {
        ping = ping + 1;
        emit updatingPing(sender, ping);
    }

    /// @dev Flow message receiver.
    /// @param account Account streaming.
    /// @param flowRate Unadjusted flow rate.

    /// @dev Rebalance message receiver.
    function receiveRebalanceMessage() external override {
        uint256 underlyingBalance = IERC20(superToken.getUnderlyingToken())
            .balanceOf(address(this));

        superToken.upgrade(underlyingBalance);

        feesPending = 0;

        emit RebalanceMessageReceived();
    }

    /// @dev Updates the pending fees, feeAccrualRate, and lastFeeAccrualUpdate on a flow call.
    /// Pending fees are set to zero because the flow message always contains the full balance of
    /// the origin pool
    function _updateFeeFlowRate(int96 feeFlowRate) internal {
        feesPending = 0;

        feeAccrualRate += feeFlowRate;

        lastFeeAccrualUpdate = block.timestamp;
    }
}
