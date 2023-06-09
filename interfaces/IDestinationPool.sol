// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.17;

interface IDestinationPool {
    function receiveFlowMessage(address, int96, uint256, uint256) external;

    function receiveRebalanceMessage() external;
}
