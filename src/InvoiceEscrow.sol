// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title InvoiceEscrow — tUSD8 invoice escrow for Aevum Builder Challenge #1
/// @notice One simple payment flow on Aevum Testnet (chain 44005):
///  1. Payer creates an invoice and locks tUSD8 in this contract (single call,
///     pulls funds via ERC-20 transferFrom — payer must approve() first).
///  2. Payee confirms receipt of the goods/services -> funds release to payee.
///  3. If the deadline passes with no confirmation, the payer can claim a refund.
/// @dev No admin, no fees, no upgradeability, no payer-cancel: once funded, the
///  payer cannot pull the money back before the deadline. That is the point of
///  escrow — the payee can ship knowing the funds are locked, and the payer is
///  protected by the deadline refund. Status transitions are one-way:
///  Funded -> Released | Funded -> Refunded.
interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract InvoiceEscrow {
    enum Status {
        Funded,
        Released,
        Refunded
    }

    struct Invoice {
        address payer;
        address payee;
        uint256 amount;
        uint256 deadline;
        Status status;
        string description;
    }

    IERC20 public immutable token;
    uint256 public invoiceCount;
    mapping(uint256 => Invoice) public invoices;

    event InvoiceCreated(
        uint256 indexed id, address indexed payer, address indexed payee, uint256 amount, uint256 deadline
    );
    event InvoiceReleased(uint256 indexed id, address indexed payee, uint256 amount);
    event InvoiceRefunded(uint256 indexed id, address indexed payer, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error SameParty();
    error DeadlineInPast();
    error NotPayee();
    error NotPayer();
    error NotFunded();
    error DeadlineNotReached();
    error TransferFailed();

    constructor(address token_) {
        if (token_ == address(0)) revert ZeroAddress();
        token = IERC20(token_);
    }

    /// @notice Create and fund an invoice in one call. Caller must have called
    ///  token.approve(address(this), amount) first.
    function createInvoice(address payee, uint256 amount, uint256 deadline, string calldata description)
        external
        returns (uint256 id)
    {
        if (payee == address(0)) revert ZeroAddress();
        if (payee == msg.sender) revert SameParty();
        if (amount == 0) revert ZeroAmount();
        if (deadline <= block.timestamp) revert DeadlineInPast();

        id = invoiceCount++;
        invoices[id] = Invoice({
            payer: msg.sender,
            payee: payee,
            amount: amount,
            deadline: deadline,
            status: Status.Funded,
            description: description
        });

        if (!token.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        emit InvoiceCreated(id, msg.sender, payee, amount, deadline);
    }

    /// @notice Payee confirms the goods/services were received. Releases funds.
    function confirmReceipt(uint256 id) external {
        Invoice storage inv = invoices[id];
        if (inv.status != Status.Funded) revert NotFunded();
        if (msg.sender != inv.payee) revert NotPayee();

        inv.status = Status.Released;
        if (!token.transfer(inv.payee, inv.amount)) revert TransferFailed();
        emit InvoiceReleased(id, inv.payee, inv.amount);
    }

    /// @notice Payer reclaims funds after the deadline passed with no confirmation.
    function claimRefund(uint256 id) external {
        Invoice storage inv = invoices[id];
        if (inv.status != Status.Funded) revert NotFunded();
        if (msg.sender != inv.payer) revert NotPayer();
        if (block.timestamp < inv.deadline) revert DeadlineNotReached();

        inv.status = Status.Refunded;
        if (!token.transfer(inv.payer, inv.amount)) revert TransferFailed();
        emit InvoiceRefunded(id, inv.payer, inv.amount);
    }

    function getInvoice(uint256 id) external view returns (Invoice memory) {
        return invoices[id];
    }
}
