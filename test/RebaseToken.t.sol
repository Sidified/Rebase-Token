// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/Interfaces/IRebaseToken.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract RebaseTokenTest is Test {
    error RebaseTokenTest__DepositFailed();
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    // We need this function because in the fuzz tests the amount of the rewards that will be given to the user is dynamic and it is based on the time that has passed
    function addRewardsToVault(uint256 rewardAmount) public {
        vm.deal(owner, rewardAmount); // Give the owner some ETH to add rewards to the vault
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
        if (!success) {
            revert RebaseTokenTest__DepositFailed();
        }
    }

    function test_DepositedAmountGrowsLinearly(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        // 1. Deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        // 2. Check our rebase token balance
        uint256 startingBalance = rebaseToken.balanceOf(user);
        console.log("Starting balance: ", startingBalance);
        assertEq(startingBalance, amount);

        // 3. warp the time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 balanceAfter1Hour = rebaseToken.balanceOf(user);
        console.log("Balance after 1 hour: ", balanceAfter1Hour);
        assertGt(balanceAfter1Hour, startingBalance);

        // 4. warp the time again by the same amount and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 balanceAfter2Hours = rebaseToken.balanceOf(user);
        console.log("Balance after 2 hours: ", balanceAfter2Hours);
        assertGt(balanceAfter2Hours, balanceAfter1Hour);

        assertApproxEqAbs(balanceAfter2Hours - balanceAfter1Hour, balanceAfter1Hour - startingBalance, 1); // this assertApproxEqAbs checks if the difference between the balance after 2 hours and the balance after 1 hour is approximately equal to the difference between the balance after 1 hour and the starting balance, with a tolerance of 1 (which means we are checking if the growth is linear)
        vm.stopPrank();
    }

    function test_redeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        // 1. Deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);

        // 2. Redeem straight away
        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(address(user).balance, amount);
        vm.stopPrank();
    }

    function test_redeemAfterSomeTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint32).max);
        depositAmount = bound(depositAmount, 1e5, type(uint32).max);
        // 1. Deposit
        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();

        // 2. Warp the time
        vm.warp(block.timestamp + time);
        uint256 balanceAfterTimeWarp = rebaseToken.balanceOf(user);
        console.log("Balance after time warp: ", balanceAfterTimeWarp);

        // 3. Add rewards to the vault
        vm.prank(owner);
        addRewardsToVault(balanceAfterTimeWarp - depositAmount);

        // 4. Redeem
        vm.prank(user);
        vault.redeem(type(uint256).max);

        uint256 ethBalanceAfterRedeem = address(user).balance;
        console.log("ETH balance after redeem: ", ethBalanceAfterRedeem);

        assertEq(ethBalanceAfterRedeem, balanceAfterTimeWarp);
        assertGt(ethBalanceAfterRedeem, depositAmount); // this checks if the user has made a profit from the interest
    }

    function test_transfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        // 1. Deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");
        uint256 user2StartingBalance = rebaseToken.balanceOf(user2);
        uint256 userStartingBalance = rebaseToken.balanceOf(user);
        assertEq(userStartingBalance, amount);
        assertEq(user2StartingBalance, 0);

        // owner reduces the interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // 2. Transfer some tokens to user2
        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        assertEq(userBalanceAfterTransfer, userStartingBalance - amountToSend);
        assertEq(user2BalanceAfterTransfer, user2StartingBalance + amountToSend);

        // check the interest rate has been inherited (5e10 not 4e10)
        assertEq(rebaseToken.getInterestRateOfUser(user2), 5e10);
        assertEq(rebaseToken.getInterestRateOfUser(user), 5e10);
    }

    function test_cannotSetInterestRateIfNotOwner(uint256 newInterestRate) public {
        vm.prank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(newInterestRate);
    }

    function test_cannotPerformMintOrBurnIfNotGrantedAccess() public {
        uint256 amount = 1e5;

        uint256 rate = rebaseToken.getInterestRateOfUser(user);

        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.mint(user, amount, rate);

        vm.prank(owner);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.burn(user, amount);
    }

    function test_getPrincipleAmount(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        // Deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        // Check the principle balance
        assertEq(rebaseToken.principleBalanceOf(user), amount);

        // Warp the time and check the principle balance again
        vm.warp(block.timestamp + 1 hours);
        assertEq(rebaseToken.principleBalanceOf(user), amount);
    }

    function test_getRebaseTokenAddress() public view {
        assertEq(vault.getRebaseTokenAddress(), address(rebaseToken));
    }

    function test_interestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInitialInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);
        vm.prank(owner);
        vm.expectPartialRevert(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector);
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getInitialInterestRate(), initialInterestRate); // check that the interest rate has not been updated
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////
    //// THE FOLLOWING TESTS ARE WRITTEN WITH THE HELP OF AI TO TAKE THE COVERAGE AS CLOSE TO 100% ////
    ///////////////////////////////////////////////////////////////////////////////////////////////////

    // Test 1 — Transfer MAX branch //
    function test_transferMaxAmount() public {
        uint256 amount = 5 ether;

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");

        vm.prank(user);
        rebaseToken.transfer(user2, type(uint256).max);

        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(rebaseToken.balanceOf(user2), amount);
    }

    // Test 2 — transferFrom functionality //
    function test_transferFrom() public {
        uint256 amount = 5 ether;

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address spender = makeAddr("spender");
        address receiver = makeAddr("receiver");

        vm.prank(user);
        rebaseToken.approve(spender, amount);

        vm.prank(spender);
        rebaseToken.transferFrom(user, receiver, amount);

        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(rebaseToken.balanceOf(receiver), amount);
    }

    // Test 3 — transferFrom MAX branch //
    function test_transferFromMaxAmount() public {
        uint256 amount = 3 ether;

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address spender = makeAddr("spender");
        address receiver = makeAddr("receiver");

        vm.prank(user);
        rebaseToken.approve(spender, type(uint256).max);

        vm.prank(spender);
        rebaseToken.transferFrom(user, receiver, type(uint256).max);

        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(rebaseToken.balanceOf(receiver), amount);
    }

    // Test 4 — Recipient already has tokens //
    function test_transferRecipientAlreadyHasBalance() public {
        uint256 amount = 5 ether;

        address user2 = makeAddr("user2");

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        vm.deal(user2, amount);
        vm.prank(user2);
        vault.deposit{value: amount}();

        vm.prank(user);
        rebaseToken.transfer(user2, 1 ether);

        assertEq(rebaseToken.balanceOf(user2), amount + 1 ether);
    }

    // Test 5 — Successful interest rate update //
    function test_ownerCanDecreaseInterestRate() public {
        uint256 newRate = 4e10;

        vm.prank(owner);
        rebaseToken.setInterestRate(newRate);

        assertEq(rebaseToken.getInitialInterestRate(), newRate);
    }

    // Test 6 — Event Test //
    function test_interestRateEventEmitted() public {
        uint256 newRate = 4e10;

        vm.expectEmit(true, false, false, true);
        emit RebaseToken.InterestRateUpdated(newRate);

        vm.prank(owner);
        rebaseToken.setInterestRate(newRate);
    }

    // Test 7 - Interest Mint Happens On Interaction //
    function test_interestMintedOnInteraction() public {
        uint256 amount = 5 ether;

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        uint256 startingPrinciple = rebaseToken.principleBalanceOf(user);

        vm.warp(block.timestamp + 1 hours);

        uint256 balanceBeforeInteraction = rebaseToken.balanceOf(user);
        uint256 principleBeforeInteraction = rebaseToken.principleBalanceOf(user);

        // interest not minted yet
        assertEq(principleBeforeInteraction, startingPrinciple);
        assertGt(balanceBeforeInteraction, startingPrinciple);

        // interaction triggers mint
        vm.prank(user);
        rebaseToken.transfer(makeAddr("user2"), 1);

        uint256 principleAfterInteraction = rebaseToken.principleBalanceOf(user);

        assertGt(principleAfterInteraction, startingPrinciple);
    }

    // Test 8 - Rebase Math Invariant //
    function test_balanceAlwaysGreaterThanPrinciple(uint256 amount, uint256 time) public {
        amount = bound(amount, 1e5, type(uint96).max);
        time = bound(time, 1 hours, 365 days);

        vm.deal(user, amount);

        vm.prank(user);
        vault.deposit{value: amount}();

        vm.warp(block.timestamp + time);

        uint256 balance = rebaseToken.balanceOf(user);
        uint256 principle = rebaseToken.principleBalanceOf(user);

        assertGe(balance, principle);
    }

    // Test 9 - User Interest Rate Snapshot Test //
    function test_userKeepsOriginalInterestRate() public {
        uint256 amount = 5 ether;

        vm.deal(user, amount);

        vm.prank(user);
        vault.deposit{value: amount}();

        uint256 userRate = rebaseToken.getInterestRateOfUser(user);

        // owner reduces interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        address user2 = makeAddr("user2");

        vm.deal(user2, amount);

        vm.prank(user2);
        vault.deposit{value: amount}();

        uint256 user2Rate = rebaseToken.getInterestRateOfUser(user2);

        // original user keeps higher rate
        assertGt(userRate, user2Rate);
    }

    // Test 10 - Vault Partial Redeem Test //
    function test_partialRedeem() public {
        uint256 amount = 5 ether;
        uint256 redeemAmount = 2 ether;

        vm.deal(user, amount);

        vm.prank(user);
        vault.deposit{value: amount}();

        vm.prank(user);
        vault.redeem(redeemAmount);

        assertEq(address(user).balance, redeemAmount);

        uint256 remainingBalance = rebaseToken.balanceOf(user);

        assertEq(remainingBalance, amount - redeemAmount);
    }
}
