// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Box} from "../src/Box.sol";
import {GovToken} from "../src/GovToken.sol";
import {TimeLock} from "../src/TimeLock.sol";

contract MyGovernorTest is Test {
    MyGovernor governor;
    Box box;
    GovToken token;
    TimeLock timelock;

    address public USER = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    uint256 public constant MIN_DELAY = 3600;
    uint256 public constant VOTING_DELAY = 7200;
    uint256 public constant VOTING_PERIOD = 50400;

    address[] public proposers;
    address[] public executors;

    uint256[] public values;
    bytes[] public calldatas;
    address[] public targets;

    function setUp() public {
        token = new GovToken();
        token.mint(USER, INITIAL_SUPPLY);

        vm.startPrank(USER);
        token.delegate(USER);
        timelock = new TimeLock(MIN_DELAY, proposers, executors);
        governor = new MyGovernor(token, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(governor));
        timelock.revokeRole(adminRole, USER);

        box = new Box(address(timelock));
        vm.stopPrank();
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(42);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 1;
        string memory description = "store 1 in box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);

        values.push(0);

        calldatas.push(encodedFunctionCall);
        targets.push(address(box));

        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        console.log("proposalId", proposalId);
        //console.log("state", governor.state(proposalId)); //pending = 0 or 1?

        // use the actual voting delay from MyGovernor
        vm.warp(block.timestamp + VOTING_DELAY * 12 + 1);
        vm.roll(block.number + VOTING_DELAY + 1); // now it should be active

        string memory reason = "reason this and that";
        //against 0
        //for 1
        //abstain 2
        uint8 voteWay = 1;
        vm.prank(USER);
        governor.castVoteWithReason(proposalId, voteWay, reason);

        //voting period is set to 1 week (50400) through UI of openzeppelin
        vm.warp(block.timestamp + VOTING_PERIOD * 12 + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // 3. queue tx
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        // advance past the timelock delay (3600 seconds)
        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + 1);

        // 4.execute tx
        console.log("box value", box.getNumber());
        governor.execute(targets, values, calldatas, descriptionHash);
        assertEq(box.getNumber(), valueToStore);
    }
}
