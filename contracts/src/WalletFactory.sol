// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {Wallet} from "./Wallet.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract WalletFactory {
    Wallet private immutable i_walletImplementation;

    constructor(address entryPointAddress) {
        i_walletImplementation = new Wallet(entryPointAddress,address(this));
    }

    /*====== External Functions ======*/
    function createAccount(address[] memory owners, uint256 salt) external returns (Wallet) {
        address addr = getAddress(owners, salt);

        uint256 codeSize = addr.code.length;
        if (codeSize > 0) {
            return Wallet(payable(addr));
        }

        bytes memory walletInit = abi.encodeCall(Wallet.initialize, owners);
        ERC1967Proxy proxy = new ERC1967Proxy{salt: bytes32(salt)}(address(i_walletImplementation),walletInit);

        return Wallet(payable(address(proxy)));
    }

    /*====== Pure / View Functions ======*/
    function getAddress(address[] memory owners, uint256 salt) public view returns (address) {
        bytes memory walletInit = abi.encodeCall(Wallet.initialize, owners);

        bytes memory proxyConstructor = abi.encode(address(i_walletImplementation), walletInit);

        // Encode the creation code for ERC1967Proxy along with the encoded proxyConstructor data
        bytes memory bytecode = abi.encodePacked(type(ERC1967Proxy).creationCode, proxyConstructor);

        // Compute the keccak256 hash of the bytecode generated
        bytes32 bytecodeHash = keccak256(bytecode);
        // Use the hash and the salt to compute the counterfactual address of the proxy
        return Create2.computeAddress(bytes32(salt), bytecodeHash);
    }
}
