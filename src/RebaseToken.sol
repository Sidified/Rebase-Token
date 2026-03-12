// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions
pragma solidity ^0.8.24;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author Sid
 * @notice This is a cross chain rebase token that can incentivise users to deposit into a vault and gain interest in reward.
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will ahve their own interest rate, which is determined by the time they deposit into the vault. The earlier they deposit, the higher their interest rate will be.
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    /// ERRORS ////
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 currentInterestRate, uint256 newInterestRate);

    /// EVENTS ////
    event InterestRateUpdated(uint256 newInterestRate);

    /// STATE VARIABLES ////
    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private s_interestRate = 5e10;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    mapping(address => uint256) private s_userInterestRates;
    mapping(address => uint256) private s_userLastUpdatedTimeStamp;

    /// FUNCTIONS ////
    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice Set the interest rate in the contract
     * @param _newInterestRate The new interest rate to be set
     * @dev The interest rate can only decrease, if the new interest rate is greater than the current interest rate, the transaction will be reverted
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // Set the interest rate
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateUpdated(_newInterestRate);
    }

    /**
     * @notice Get the principle balance of a user. This is the number of tokens that have currenlty been minted to the user, which does not include any interest that has accumulated since the last time the user's balance was updated
     * @param _user The address of the user
     * @return The principle balance of the user
     */
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Mint rebase tokens to a user when they deposit into the vault
     * @param _to The address of the user to mint the tokens to
     * @param _amount The amount of tokens to be minted
     *
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRates[_to] = _userInterestRate;
        _mint(_to, _amount);

        // AI gave this suggestio -> To be 100% precise, most devs would mint the interest first, then check for the "Max" flag to ensure the balanceOf calculation is acting on the most up-to-date state.
    }

    /**
     * @notice Burn rebase tokens from a user when they withdraw from the vault
     * @param _from The address of the user to burn the tokens from
     * @param _amount The amount of tokens to be burned
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice calculates the balance of a user including the interest that has accumulated since the last time the user's balance was updated
     * (principle balance) + some interest that has accrued
     * @param _user The address of the user
     * @return The balance of the user including the interest that has accumulated since the last time the user's balance was updated
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // get the current principle balance of the user (the number of tokens that have actually been minted to the user)
        // multiply the principle balance by the interest that has accumulated in the time since the balance was last updated
        return (super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user)) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfer rebase tokens from one user to another
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to be transferred
     * @return True if the transfer is successful, false otherwise
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRates[_recipient] = s_userInterestRates[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfer rebase tokens from one user to another on behalf of the sender
     * @param _sender The address of the sender
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to be transferred
     * @return True if the transfer is successful, false otherwise
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRates[_recipient] = s_userInterestRates[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice calculates the interest that has accumulated for a user since the last time their balance was updated
     * @param _user The address of the user
     * @return  linearInterest The interest that has accumulated for the user since the last time their balance was updated
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        // we need to calculate the interest that has accumulated for the user since the last time their balance was updated
        // this is going to be linear growth with time
        // 1. Calculate the time since the last update
        // 2. Calculate the ammount of linear growth
        // principle balance + (principle balance * interest rate * time since last update)
        // ex -> principle balance = 100 tokens, interest rate = 10% per second, time since last update = 10 seconds
        // 100 + (100 * 10% * 10) = 200 tokens

        uint256 timeSinceLastUpdate = block.timestamp - s_userLastUpdatedTimeStamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRates[_user] * timeSinceLastUpdate);
    }

    /**
     * @notice Mint the accrued interest to the user since the last time they interacted with the protocol (e.g. burn, mint, transfer)
     * @param _user The address of the user
     */
    function _mintAccruedInterest(address _user) internal {
        // (1) find their current balance of rebase tokens that have been minted to the user -> principle balance
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // (2) calculate their current balance including any interest -> balanceOf
        uint256 currentBalance = balanceOf(_user);
        // calculate the number of tokens that need to be minted to the user -> (2) - (1)
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        // call _mint function to mint the number of tokens to the user
        // set the user's last updated timeStamp
        s_userLastUpdatedTimeStamp[_user] = block.timestamp;
        _mint(_user, balanceIncrease);
    }

    /// GETTER FUNCTIONS ///
    /**
     * @notice Get the interest rate of a user
     * @param _user The address of the user
     * @return The interest rate of the user
     */
    function getInterestRateOfUser(address _user) external view returns (uint256) {
        return s_userInterestRates[_user];
    }

    /**
     * @notice Get the interest rate that is currently set for the contract. Any future depositors will receive this interest rate
     * @return The interest rate that is currently set for the contract
     */
    function getInitialInterestRate() external view returns (uint256) {
        return s_interestRate;
    }
}
