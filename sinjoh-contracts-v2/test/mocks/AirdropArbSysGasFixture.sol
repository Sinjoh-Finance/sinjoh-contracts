// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
/// Test-only ArbSys substitute for Anvil gas measurements; never a deployment input.
contract AirdropArbSysGasFixture {
    function arbBlockNumber() external view returns(uint256){return block.number;}
    function arbBlockHash(uint256 number) external view returns(bytes32){return blockhash(number);}
}
