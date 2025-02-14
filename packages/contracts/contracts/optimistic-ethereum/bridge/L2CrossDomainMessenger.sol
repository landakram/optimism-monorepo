pragma solidity ^0.5.0;

/* Interface Imports */
import { IL2CrossDomainMessenger } from "./L2CrossDomainMessenger.interface.sol";
import { IL1MessageSender } from "../ovm/precompiles/L1MessageSender.interface.sol";
import { IL2ToL1MessagePasser } from "../ovm/precompiles/L2ToL1MessagePasser.interface.sol";

/* Contract Imports */
import { BaseCrossDomainMessenger } from "./BaseCrossDomainMessenger.sol";

/**
 * @title L2CrossDomainMessenger
 */
contract L2CrossDomainMessenger is IL2CrossDomainMessenger, BaseCrossDomainMessenger{
    /*
     * Contract Variables
     */

    address private l1MessageSenderPrecompileAddress;
    address private l2ToL1MessagePasserPrecompileAddress;


    /*
     * Constructor
     */

    /** 
     * @param _l1MessageSenderPrecompileAddress L1MessageSender address.
     * @param _l2ToL1MessagePasserPrecompileAddress L2ToL1MessagePasser address.
     */
    constructor(
        address _l1MessageSenderPrecompileAddress,
        address _l2ToL1MessagePasserPrecompileAddress
    )
        public
    {
        l1MessageSenderPrecompileAddress = _l1MessageSenderPrecompileAddress;
        l2ToL1MessagePasserPrecompileAddress = _l2ToL1MessagePasserPrecompileAddress;
    }


    /*
     * Public Functions
     */

    /**
     * Sends a cross domain message to the target messenger.
     * .inheritdoc IL2CrossDomainMessenger
     */
    function sendMessage(
        address _target,
        bytes memory _message,
        uint256 _gasLimit
    )
        public
    {
        bytes memory xDomainCalldata = _getXDomainCalldata(
            _target,
            msg.sender,
            _message,
            messageNonce
        );

        _sendXDomainMessage(xDomainCalldata, _gasLimit);

        messageNonce += 1;
        sentMessages[keccak256(xDomainCalldata)] = true;
    }

    /**
     * Relays a cross domain message to a contract.
     * .inheritdoc IL2CrossDomainMessenger
     */
    function relayMessage(
        address _target,
        address _sender,
        bytes memory _message,
        uint256 _messageNonce
    )
        public
    {
        require(
            _verifyXDomainMessage() == true,
            "Provided message could not be verified."
        );

        bytes memory xDomainCalldata = _getXDomainCalldata(
            _target,
            _sender,
            _message,
            _messageNonce
        );

        require(
            receivedMessages[keccak256(xDomainCalldata)] == false,
            "Provided message has already been received."
        );

        xDomainMessageSender = _sender;
        _target.call(_message);

        // Messages are considered successfully executed if they complete
        // without running out of gas (revert or not). As a result, we can
        // ignore the result of the call and always mark the message as
        // successfully executed because we won't get here unless we have
        // enough gas left over.
        receivedMessages[keccak256(xDomainCalldata)] = true;
    }


    /*
     * Internal Functions
     */

    /**
     * Verifies that a received cross domain message is valid.
     * @return Whether or not the message is valid.
     */
    function _verifyXDomainMessage()
        internal
        returns (
            bool
        )
    {
        IL1MessageSender l1MessageSenderPrecompile = IL1MessageSender(l1MessageSenderPrecompileAddress);
        address l1MessageSenderAddress = l1MessageSenderPrecompile.getL1MessageSender();
        return l1MessageSenderAddress == targetMessengerAddress;
    }

    /**
     * Sends a cross domain message.
     * @param _message Message to send.
     * @param _gasLimit Gas limit for the provided message.
     */
    function _sendXDomainMessage(
        bytes memory _message,
        uint256 _gasLimit
    )
        internal
    {
        IL2ToL1MessagePasser l2ToL1MessagePasserPrecompile = IL2ToL1MessagePasser(l2ToL1MessagePasserPrecompileAddress);
        l2ToL1MessagePasserPrecompile.passMessageToL1(_message);
    }
}
