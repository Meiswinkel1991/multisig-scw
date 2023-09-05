// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {BaseAccount} from "account-abstraction/core/BaseAccount.sol";
import {UserOperation} from "account-abstraction/interfaces/UserOperation.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {TokenCallbackHandler} from "account-abstraction/samples/callback/TokenCallbackHandler.sol";

contract Wallet is BaseAccount, Initializable, TokenCallbackHandler {
    using ECDSA for bytes32;

    /*====== Errors ======*/
    error Wallet__NoOwners();
    error Wallet_NotEntryPointOrFactory();
    error Wallet_WrongDestLength();
    error Wallet__WrongValuesLength();

    /* ====== State Variables ====== */
    address public immutable i_walletFactory;

    IEntryPoint private immutable i_entryPoint;

    address[] private s_owners;

    /*====== Events ======*/
    event WalletInitialized(IEntryPoint indexed entryPoint, address[] owners);

    /*====== Modifiers ======*/
    modifier requireFromEntryPointOrFactory() {
        if (msg.sender != address(i_entryPoint) || msg.sender != i_walletFactory) {
            revert Wallet_NotEntryPointOrFactory();
        }
        _;
    }

    /*====== FUNCTIONS ====== */

    constructor(address entryPointAddress, address walletFactory) {
        i_walletFactory = walletFactory;

        i_entryPoint = IEntryPoint(entryPointAddress);
    }

    receive() external payable {}

    /*====== External Functions ======*/
    function execute(address dest, uint256 value, bytes calldata func) external requireFromEntryPointOrFactory {
        _call(dest, value, func);
    }

    function executeBatch(address[] calldata dests, uint256[] calldata values, bytes[] calldata funcs)
        external
        requireFromEntryPointOrFactory
    {
        if (dests.length != funcs.length) {
            revert Wallet_WrongDestLength();
        }
        if (values.length != funcs.length) {
            revert Wallet__WrongValuesLength();
        }

        for (uint256 i = 0; i < dests.length; i++) {
            _call(dests[i], values[i], funcs[i]);
        }
    }

    function initialize(address[] memory initialOwners) external initializer {}

    function addDeposit() public payable {
        entryPoint().depositTo{value: msg.value}(address(this));
    }

    /*====== Internal Functions ======*/
    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        override
        returns (uint256)
    {
        // Convert the userOpHash to an Ethereum Signed Message Hash
        bytes32 hash = userOpHash.toEthSignedMessageHash();

        // Decode  the signatures from the userOp and store then in a bytes array in memory
        bytes[] memory signatures = abi.decode(userOp.signature, (bytes[]));

        //Loop through all the owner of the wallet
        address[] memory owners = s_owners;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] != hash.recover(signatures[i])) {
                return SIG_VALIDATION_FAILED;
            }
        }

        return 0;
    }

    function _initialize(address[] memory initialOwners) internal {
        if (initialOwners.length == 0) {
            revert Wallet__NoOwners();
        }

        s_owners = initialOwners;

        emit WalletInitialized(i_entryPoint, initialOwners);
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);

        if (!success) {
            assembly {
                // The assembly code here skips the first 32 bytes of the result, which contains the length of data.
                // It then loads the actual error message using mload and calls revert with this error message.
                revert(add(result, 32), mload(result))
            }
        }
    }

    /*====== Pure / View Functions ======*/
    function entryPoint() public view override returns (IEntryPoint) {
        return i_entryPoint;
    }

    function encodeSignatures(bytes[] memory signatures) public pure returns (bytes memory) {
        return abi.encode(signatures);
    }

    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }
}
