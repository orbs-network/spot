// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FeeOnTransferERC20Mock is ERC20 {
    uint256 public feeBps;
    address public feeRecipient;

    constructor(string memory name_, string memory symbol_, uint256 feeBps_, address feeRecipient_)
        ERC20(name_, symbol_)
    {
        feeBps = feeBps_;
        feeRecipient = feeRecipient_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setFeeBps(uint256 feeBps_) external {
        feeBps = feeBps_;
    }

    function setFeeRecipient(address feeRecipient_) external {
        feeRecipient = feeRecipient_;
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from == address(0) || to == address(0) || amount == 0 || feeBps == 0) {
            super._update(from, to, amount);
            return;
        }

        uint256 fee = (amount * feeBps) / 10_000;
        uint256 sendAmount = amount - fee;

        if (fee != 0) {
            if (feeRecipient == address(0)) {
                super._update(from, address(0), fee);
            } else {
                super._update(from, feeRecipient, fee);
            }
        }

        super._update(from, to, sendAmount);
    }
}
