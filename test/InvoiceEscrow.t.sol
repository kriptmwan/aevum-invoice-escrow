// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/InvoiceEscrow.sol";

/// @notice Minimal ERC-20 mock with 6 decimals, matching tUSD8's interface surface.
contract MockUSD {
    string public name = "Mock tUSD8";
    string public symbol = "tUSD8";
    uint8 public decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient balance");
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract InvoiceEscrowTest is Test {
    InvoiceEscrow escrow;
    MockUSD token;
    address payer = address(0xA11CE);
    address payee = address(0xBEEF);
    address stranger = address(0xCAFE);
    uint256 constant AMOUNT = 100_000_000; // 100.000000 tUSD8 (6 decimals)

    event InvoiceCreated(
        uint256 indexed id, address indexed payer, address indexed payee, uint256 amount, uint256 deadline
    );
    event InvoiceReleased(uint256 indexed id, address indexed payee, uint256 amount);
    event InvoiceRefunded(uint256 indexed id, address indexed payer, uint256 amount);

    function setUp() public {
        token = new MockUSD();
        escrow = new InvoiceEscrow(address(token));
        token.mint(payer, 1_000_000_000); // 1,000 tUSD8
        vm.prank(payer);
        token.approve(address(escrow), type(uint256).max);
    }

    function _create(uint256 amount, uint256 deadline) internal returns (uint256 id) {
        vm.prank(payer);
        id = escrow.createInvoice(payee, amount, deadline, "Test invoice");
    }

    // --- happy path ---

    function testCreateAndRelease() public {
        uint256 deadline = block.timestamp + 7 days;
        vm.expectEmit(true, true, true, true, address(escrow));
        emit InvoiceCreated(0, payer, payee, AMOUNT, deadline);
        uint256 id = _create(AMOUNT, deadline);

        assertEq(id, 0);
        assertEq(token.balanceOf(address(escrow)), AMOUNT);
        assertEq(token.balanceOf(payer), 1_000_000_000 - AMOUNT);

        vm.expectEmit(true, true, false, true, address(escrow));
        emit InvoiceReleased(0, payee, AMOUNT);
        vm.prank(payee);
        escrow.confirmReceipt(id);

        assertEq(token.balanceOf(payee), AMOUNT);
        assertEq(token.balanceOf(address(escrow)), 0);
        InvoiceEscrow.Invoice memory inv = escrow.getInvoice(id);
        assertEq(uint256(inv.status), uint256(InvoiceEscrow.Status.Released));
    }

    // --- refund path ---

    function testRefundAfterDeadline() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 id = _create(AMOUNT, deadline);

        vm.warp(deadline + 1);
        vm.expectEmit(true, true, false, true, address(escrow));
        emit InvoiceRefunded(0, payer, AMOUNT);
        vm.prank(payer);
        escrow.claimRefund(id);

        assertEq(token.balanceOf(payer), 1_000_000_000);
        assertEq(token.balanceOf(address(escrow)), 0);
        InvoiceEscrow.Invoice memory inv = escrow.getInvoice(id);
        assertEq(uint256(inv.status), uint256(InvoiceEscrow.Status.Refunded));
    }

    function testRefundBeforeDeadlineReverts() public {
        uint256 id = _create(AMOUNT, block.timestamp + 1 days);
        vm.prank(payer);
        vm.expectRevert(InvoiceEscrow.DeadlineNotReached.selector);
        escrow.claimRefund(id);
    }

    // --- access control ---

    function testConfirmByNonPayeeReverts() public {
        uint256 id = _create(AMOUNT, block.timestamp + 1 days);
        vm.prank(payer);
        vm.expectRevert(InvoiceEscrow.NotPayee.selector);
        escrow.confirmReceipt(id);
        vm.prank(stranger);
        vm.expectRevert(InvoiceEscrow.NotPayee.selector);
        escrow.confirmReceipt(id);
    }

    function testRefundByNonPayerReverts() public {
        uint256 id = _create(AMOUNT, block.timestamp + 1 days);
        vm.warp(block.timestamp + 2 days);
        vm.prank(payee);
        vm.expectRevert(InvoiceEscrow.NotPayer.selector);
        escrow.claimRefund(id);
    }

    // --- double-spend guards ---

    function testDoubleConfirmReverts() public {
        uint256 id = _create(AMOUNT, block.timestamp + 1 days);
        vm.prank(payee);
        escrow.confirmReceipt(id);
        vm.prank(payee);
        vm.expectRevert(InvoiceEscrow.NotFunded.selector);
        escrow.confirmReceipt(id);
    }

    function testDoubleRefundReverts() public {
        uint256 id = _create(AMOUNT, block.timestamp + 1 days);
        vm.warp(block.timestamp + 2 days);
        vm.prank(payer);
        escrow.claimRefund(id);
        vm.prank(payer);
        vm.expectRevert(InvoiceEscrow.NotFunded.selector);
        escrow.claimRefund(id);
    }

    function testConfirmAfterRefundReverts() public {
        uint256 id = _create(AMOUNT, block.timestamp + 1 days);
        vm.warp(block.timestamp + 2 days);
        vm.prank(payer);
        escrow.claimRefund(id);
        vm.prank(payee);
        vm.expectRevert(InvoiceEscrow.NotFunded.selector);
        escrow.confirmReceipt(id);
    }

    function testRefundAfterReleaseReverts() public {
        uint256 id = _create(AMOUNT, block.timestamp + 1 days);
        vm.prank(payee);
        escrow.confirmReceipt(id);
        vm.warp(block.timestamp + 2 days);
        vm.prank(payer);
        vm.expectRevert(InvoiceEscrow.NotFunded.selector);
        escrow.claimRefund(id);
    }

    // --- creation guards ---

    function testCreateZeroAmountReverts() public {
        vm.prank(payer);
        vm.expectRevert(InvoiceEscrow.ZeroAmount.selector);
        escrow.createInvoice(payee, 0, block.timestamp + 1 days, "zero");
    }

    function testCreateZeroPayeeReverts() public {
        vm.prank(payer);
        vm.expectRevert(InvoiceEscrow.ZeroAddress.selector);
        escrow.createInvoice(address(0), AMOUNT, block.timestamp + 1 days, "zero payee");
    }

    function testCreateSelfPayeeReverts() public {
        vm.prank(payer);
        vm.expectRevert(InvoiceEscrow.SameParty.selector);
        escrow.createInvoice(payer, AMOUNT, block.timestamp + 1 days, "self");
    }

    function testCreatePastDeadlineReverts() public {
        vm.prank(payer);
        vm.expectRevert(InvoiceEscrow.DeadlineInPast.selector);
        escrow.createInvoice(payee, AMOUNT, block.timestamp, "past");
    }

    function testCreateWithoutAllowanceReverts() public {
        address poor = address(0xD00D);
        token.mint(poor, AMOUNT);
        // poor never approved the escrow
        vm.prank(poor);
        vm.expectRevert("insufficient allowance");
        escrow.createInvoice(payee, AMOUNT, block.timestamp + 1 days, "no approval");
    }

    function testCreateWithoutBalanceReverts() public {
        address poor = address(0xD00D);
        vm.prank(poor);
        token.approve(address(escrow), type(uint256).max);
        vm.prank(poor);
        vm.expectRevert("insufficient balance");
        escrow.createInvoice(payee, AMOUNT, block.timestamp + 1 days, "no funds");
    }

    // --- constructor + multiple invoices ---

    function testConstructorZeroTokenReverts() public {
        vm.expectRevert(InvoiceEscrow.ZeroAddress.selector);
        new InvoiceEscrow(address(0));
    }

    function testMultipleInvoicesIndependent() public {
        uint256 id0 = _create(AMOUNT, block.timestamp + 1 days);
        uint256 id1 = _create(50_000_000, block.timestamp + 2 days);
        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(escrow.invoiceCount(), 2);

        // release the second, refund the first after its deadline
        vm.prank(payee);
        escrow.confirmReceipt(id1);
        assertEq(token.balanceOf(payee), 50_000_000);
        vm.warp(block.timestamp + 2 days);
        vm.prank(payer);
        escrow.claimRefund(id0);
        assertEq(token.balanceOf(payer), 1_000_000_000 - 50_000_000);
    }
}
