// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ProjectIds } from "../../src/libraries/ProjectIds.sol";
import { SinjohV2Constants } from "../../src/libraries/SinjohV2Constants.sol";

contract MockProjectToken is ERC20 {
    address public immutable registry;
    bytes32 public immutable projectId;
    uint16 public transferFeeBps;

    constructor(address registry_, address recipient, uint256 supply)
        ERC20("Mock Project Token", "MPT")
    {
        registry = registry_;
        projectId = ProjectIds.derive(block.chainid, registry_, address(this));
        _mint(recipient, supply);
    }

    function setTransferFeeBps(uint16 feeBps) external {
        transferFeeBps = feeBps;
    }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function _update(address from, address to, uint256 amount) internal override {
        uint256 fee = from != address(0) && to != address(0) ? amount * transferFeeBps / 10_000 : 0;
        if (fee != 0) {
            super._update(from, SinjohV2Constants.BURN_ADDRESS, fee);
            amount -= fee;
        }
        super._update(from, to, amount);
    }
}
