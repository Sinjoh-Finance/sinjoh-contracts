// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {AirdropVault} from "./AirdropVault.sol";
import {AirdropTargetBook} from "./AirdropTargetBook.sol";
import {AirdropAssetRegistry} from "./AirdropAssetRegistry.sol";
interface IAirdropCustodySleeveIdentity {
    function collection() external view returns(address);
    function governance() external view returns(address);
}

/// @notice Creates custody after sleeve materialization inside the SAME governance batch.
/// @dev Addresses are determined before queueing. Governance connects them to the sleeve
/// in subsequent calls in that batch. This factory holds no funds or bank authority.
contract AirdropCustodyFactory {
    address public immutable governance;
    error Unauthorized();
    error InvalidConfiguration();
    event CustodyInfrastructureCreated(address indexed sleeve,address vault,address targetBook,bytes32 salt);
    constructor(address governance_){if(governance_==address(0))revert InvalidConfiguration();governance=governance_;}
    function predict(address sleeve,address collection,address registry,bytes32 salt) public view returns(address vault,address book){
        vault=Create2.computeAddress(keccak256(abi.encode(salt,"vault")),keccak256(abi.encodePacked(type(AirdropVault).creationCode,abi.encode(sleeve,collection,registry))));
        book=Create2.computeAddress(keccak256(abi.encode(salt,"target-book")),keccak256(abi.encodePacked(type(AirdropTargetBook).creationCode,abi.encode(sleeve))));
    }
    function deploy(address sleeve,address collection,address registry,bytes32 salt) external returns(address vault,address book){
        if(msg.sender!=governance)revert Unauthorized();
        if(sleeve.code.length==0||collection.code.length==0||registry.code.length==0||salt==bytes32(0)
            ||IAirdropCustodySleeveIdentity(sleeve).collection()!=collection
            ||IAirdropCustodySleeveIdentity(sleeve).governance()!=governance
            ||AirdropAssetRegistry(registry).owner()!=governance)revert InvalidConfiguration();
        (address expectedVault,address expectedBook)=predict(sleeve,collection,registry,salt);
        vault=address(new AirdropVault{salt:keccak256(abi.encode(salt,"vault"))}(sleeve,collection,registry));
        book=address(new AirdropTargetBook{salt:keccak256(abi.encode(salt,"target-book"))}(sleeve));
        if(vault!=expectedVault||book!=expectedBook)revert InvalidConfiguration();
        emit CustodyInfrastructureCreated(sleeve,vault,book,salt);
    }
}
