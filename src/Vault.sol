// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {IRebaseToken} from "./Interfaces/IRebaseToken.sol";

contract Vault {
    // we need to pass the token addres to the constructor
    // create a deposit function that mints tokens to the user equal to the amount of ETH the user has sent
    // create a redeem function that burns token from the user and sends the user ETH
    // creata a way to add the rewards to the vault

    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    error Vault__RedeemFailed();

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }
    receive() external payable {}

    /**
     * @notice Deposit ETH into the vault and mint rebase tokens to the user
     */
    function deposit() external payable {
        // we need to use the amount of ETH the user has sent to mint tokens to the user
        uint256 interestRate = i_rebaseToken.getInterestRateOfUser(msg.sender);
        if (interestRate == 0) {
            interestRate = i_rebaseToken.getInitialInterestRate();
        }
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Redeem rebase tokens from the user and send the user ETH
     * @param _amount The amount of tokens to be redeemed
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        // 1. Burn the token from the user
        i_rebaseToken.burn(msg.sender, _amount);
        // 2. Send the user ETH equal to the amount of tokens burned
        (bool success,) = msg.sender.call{value: _amount}("");

        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    /**
     * @notice Get the address of the rebase token contract
     * @return The address of the rebase token contract
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
