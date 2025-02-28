// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ERC721Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IIPAssetRegistry } from "@storyprotocol/core/interfaces/registries/IIPAssetRegistry.sol";

contract LoanManager is UUPSUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    // Roles for access control
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant LOAN_APPROVER_ROLE = keccak256("LOAN_APPROVER_ROLE");

    // Immutable references to external contracts
    IIPAssetRegistry public immutable IP_ASSET_REGISTRY;
    IERC20 public immutable USDC;

    // Loan structure
    struct Loan {
        address borrower;         // Address of the borrower
        uint256 ipAssetId;        // Token ID of the IP asset NFT in IPAssetRegistry
        uint256 loanAmount;       // Amount lent in USDC
        uint256 interestRate;     // Interest rate in basis points (e.g., 500 = 5%)
        uint256 repaymentPeriod;  // Duration in seconds
        uint256 startTime;        // Timestamp when loan becomes active
        uint256 endTime;          // Timestamp when loan is due
        bool isActive;            // Loan status
        bool isRepaid;            // Repayment status
    }

    // State variables
    uint256 public loanCounter;          // Incremental loan ID
    mapping(uint256 => Loan) public loans; // Loan ID to Loan details

    // Events
    event LoanApplied(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 indexed ipAssetId,
        uint256 loanAmount,
        uint256 interestRate,
        uint256 repaymentPeriod
    );
    event LoanApproved(uint256 indexed loanId);
    event LoanRepaid(uint256 indexed loanId);
    event CollateralLiquidated(uint256 indexed loanId, address recipient);

    // Constructor sets immutable references
    constructor(address ipAssetRegistry, address usdc) {
        IP_ASSET_REGISTRY = IIPAssetRegistry(ipAssetRegistry);
        USDC = IERC20(usdc);
        _disableInitializers(); // Prevents initialization outside of proxy
    }

    // Initialize the upgradeable contract
    function initialize() external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(LOAN_APPROVER_ROLE, msg.sender);
    }

    // Apply for a loan by locking an IP asset
    function applyForLoan(
        uint256 ipAssetId,
        uint256 loanAmount,
        uint256 interestRate,
        uint256 repaymentPeriod
    ) external {
        require(ERC721Upgradeable(address(IP_ASSET_REGISTRY)).ownerOf(ipAssetId) == msg.sender, "Not IP asset owner");
        // Transfer the IP asset NFT to this contract as collateral
        ERC721Upgradeable(address(IP_ASSET_REGISTRY)).transferFrom(msg.sender, address(this), ipAssetId);

        uint256 loanId = loanCounter++;
        loans[loanId] = Loan({
            borrower: msg.sender,
            ipAssetId: ipAssetId,
            loanAmount: loanAmount,
            interestRate: interestRate,
            repaymentPeriod: repaymentPeriod,
            startTime: 0,
            endTime: 0,
            isActive: false,
            isRepaid: false
        });

        emit LoanApplied(loanId, msg.sender, ipAssetId, loanAmount, interestRate, repaymentPeriod);
    }

    // Approve a loan and disburse funds
    function approveLoan(uint256 loanId) external onlyRole(LOAN_APPROVER_ROLE) {
        Loan storage loan = loans[loanId];
        require(!loan.isActive, "Loan already active");
        require(!loan.isRepaid, "Loan already repaid");

        loan.isActive = true;
        loan.startTime = block.timestamp;
        loan.endTime = block.timestamp + loan.repaymentPeriod;

        // Transfer USDC from contract to borrower
        USDC.safeTransfer(loan.borrower, loan.loanAmount);

        emit LoanApproved(loanId);
    }

    // Repay a loan and unlock collateral
    function repayLoan(uint256 loanId) external {
        Loan storage loan = loans[loanId];
        require(loan.isActive, "Loan not active");
        require(!loan.isRepaid, "Loan already repaid");
        require(block.timestamp <= loan.endTime, "Loan period ended");
        require(loan.borrower == msg.sender, "Not borrower");

        // Calculate total repayment (principal + simple interest)
        uint256 totalRepayment = loan.loanAmount + (loan.loanAmount * loan.interestRate / 10000);
        USDC.safeTransferFrom(msg.sender, address(this), totalRepayment);

        loan.isRepaid = true;
        // Return the IP asset NFT to the borrower
        ERC721Upgradeable(address(IP_ASSET_REGISTRY)).transferFrom(address(this), loan.borrower, loan.ipAssetId);

        emit LoanRepaid(loanId);
    }

    // Liquidate collateral if loan defaults
    function liquidateCollateral(uint256 loanId) external onlyRole(ADMIN_ROLE) {
        Loan storage loan = loans[loanId];
        require(loan.isActive, "Loan not active");
        require(!loan.isRepaid, "Loan already repaid");
        require(block.timestamp > loan.endTime, "Loan period not ended");

        // For MVP, transfer collateral to admin; later can be auctioned or transferred to lender
        ERC721Upgradeable(address(IP_ASSET_REGISTRY)).transferFrom(address(this), msg.sender, loan.ipAssetId);
        loan.isActive = false;

        emit CollateralLiquidated(loanId, msg.sender);
    }

    // UUPS upgrade authorization
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}