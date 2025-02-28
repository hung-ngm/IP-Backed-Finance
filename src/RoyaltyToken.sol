// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IIPAssetRegistry } from "@storyprotocol/core/interfaces/registries/IIPAssetRegistry.sol";
import { IRoyaltyModule } from "@storyprotocol/core/interfaces/modules/royalty/IRoyaltyModule.sol";
import { ERC721Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

contract RoyaltyToken is UUPSUpgradeable, AccessControlUpgradeable, ERC1155Upgradeable {
    using SafeERC20 for IERC20;

    // Roles for access control
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Immutable references to external contracts
    IIPAssetRegistry public immutable IP_ASSET_REGISTRY;
    IRoyaltyModule public immutable ROYALTY_MODULE;
    IERC20 public immutable ROYALTY_TOKEN; // Stablecoin paid as royalties (e.g., USDC)

    // Struct to store token issuance details
    struct TokenInfo {
        uint256 ipAssetId;    // IP asset token ID
        uint256 percentage;   // Percentage of royalties tokenized
        uint256 totalSupply;  // Total tokens issued
    }

    // State variables
    mapping(uint256 => TokenInfo) public tokenInfo;           // Token ID to details
    mapping(uint256 => uint256) public accumulatedRoyalties;  // Token ID to accumulated royalty tokens

    // Events
    event TokensIssued(
        uint256 indexed tokenId,
        uint256 indexed ipAssetId,
        uint256 percentage,
        uint256 amount
    );
    event RoyaltiesClaimed(
        uint256 indexed tokenId,
        address indexed claimant,
        uint256 amount
    );

    // Constructor sets immutable references
    constructor(address ipAssetRegistry, address royaltyModule, address royaltyToken) {
        IP_ASSET_REGISTRY = IIPAssetRegistry(ipAssetRegistry);
        ROYALTY_MODULE = IRoyaltyModule(royaltyModule);
        ROYALTY_TOKEN = IERC20(royaltyToken);
        _disableInitializers();
    }

    // Initialize the upgradeable contract
    function initialize() external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ERC1155_init(""); // URI can be set later if needed
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    // Issue royalty tokens for an IP asset
    function issueTokens(
        uint256 ipAssetId,
        uint256 percentage,
        uint256 amount
    ) external {
        require(ERC721Upgradeable(address(IP_ASSET_REGISTRY)).ownerOf(ipAssetId) == msg.sender, "Not IP asset owner");
        require(percentage <= 10000, "Percentage exceeds 100%"); // Basis points (10000 = 100%)

        // Generate a unique token ID based on IP asset and percentage
        uint256 tokenId = uint256(keccak256(abi.encodePacked(ipAssetId, percentage)));
        require(tokenInfo[tokenId].totalSupply == 0, "Tokens already issued for this config");

        tokenInfo[tokenId] = TokenInfo({
            ipAssetId: ipAssetId,
            percentage: percentage,
            totalSupply: amount
        });

        // Mint ERC1155 tokens to the IP owner
        _mint(msg.sender, tokenId, amount, "");

        // Placeholder for RoyaltyModule integration
        // Ideally: ROYALTY_MODULE.setRoyaltyRecipient(ipAssetId, address(this), percentage);
        // For MVP, assume royalties are manually sent to this contract

        emit TokensIssued(tokenId, ipAssetId, percentage, amount);
    }

    // Receive royalties from RoyaltyModule (manual for MVP)
    function depositRoyalties(uint256 tokenId, uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(tokenInfo[tokenId].totalSupply > 0, "Invalid token ID");
        ROYALTY_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        accumulatedRoyalties[tokenId] += amount;
    }

    // Claim royalties based on token holdings
    function claimRoyalties(uint256 tokenId) external {
        uint256 balance = balanceOf(msg.sender, tokenId);
        require(balance > 0, "No tokens held");

        TokenInfo memory info = tokenInfo[tokenId];
        require(info.totalSupply > 0, "Invalid token ID");

        uint256 totalRoyalties = accumulatedRoyalties[tokenId];
        uint256 claimable = (totalRoyalties * balance) / info.totalSupply;
        require(claimable > 0, "No royalties to claim");

        accumulatedRoyalties[tokenId] -= claimable;
        ROYALTY_TOKEN.safeTransfer(msg.sender, claimable);

        emit RoyaltiesClaimed(tokenId, msg.sender, claimable);
    }

    // UUPS upgrade authorization
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    /**
     * @dev See {IERC165-supportsInterface}.
     * Overrides function from both ERC1155Upgradeable and AccessControlUpgradeable
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable, ERC1155Upgradeable)
        returns (bool)
    {
        return
            AccessControlUpgradeable.supportsInterface(interfaceId) ||
            ERC1155Upgradeable.supportsInterface(interfaceId);
    }
}