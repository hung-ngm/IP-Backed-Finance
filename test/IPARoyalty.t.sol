// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { LicenseToken } from "@storyprotocol/core/LicenseToken.sol";
import { LicensingModule } from "@storyprotocol/core/modules/licensing/LicensingModule.sol";
import { IPAssetRegistry } from "@storyprotocol/core/registries/IPAssetRegistry.sol";
import { LicenseRegistry } from "@storyprotocol/core/registries/LicenseRegistry.sol";
import { PILFlavors } from "@storyprotocol/core/lib/PILFlavors.sol";
import { PILicenseTemplate } from "@storyprotocol/core/modules/licensing/PILicenseTemplate.sol";
import { RoyaltyModule } from "@storyprotocol/core/modules/royalty/RoyaltyModule.sol";
import { IRoyaltyWorkflows } from "@storyprotocol/periphery/interfaces/workflows/IRoyaltyWorkflows.sol";
import { RoyaltyWorkflows } from "@storyprotocol/periphery/workflows/RoyaltyWorkflows.sol";
import { LicenseAttachmentWorkflows } from "@storyprotocol/periphery/workflows/LicenseAttachmentWorkflows.sol";
import { SimpleNFT } from "../src/SimpleNFT.sol";
import { SUSD } from "../src/SUSD.sol";

// Run this test: forge test --fork-url https://testnet.storyrpc.io/ --match-path test/IPARoyalty.t.sol
contract IPARoyaltyTest is Test {
    address internal alice = address(0xa11ce);
    address internal bob = address(0xb0b);

    // For addresses, see https://docs.storyprotocol.xyz/docs/deployed-smart-contracts
    // Protocol Core - IPAssetRegistry
    address internal ipAssetRegistryAddr = 0x1a9d0d28a0422F26D31Be72Edc6f13ea4371E11B;
    // Protocol Core - LicensingModule
    address internal licensingModuleAddr = 0xd81fd78f557b457b4350cB95D20b547bFEb4D857;
    // Protocol Core - LicenseRegistry
    address internal licenseRegistryAddr = 0xedf8e338F05f7B1b857C3a8d3a0aBB4bc2c41723;
    // Protocol Core - LicenseToken
    address internal licenseTokenAddr = 0xc7A302E03cd7A304394B401192bfED872af501BE;
    // Protocol Core - PILicenseTemplate
    address internal pilTemplateAddr = 0x0752f61E59fD2D39193a74610F1bd9a6Ade2E3f9;
    // Protocol Periphery - RoyaltyWorkflows
    address internal royaltyWorkflowsAddr = 0x24f571e4982163bC166E594De289D6b754cB82A5;
    // Protocol Periphery - LicenseAttachmentWorkflows
    address internal licenseAttachmentWorkflowsAddr = 0x96D26F998a56D6Ee34Fb581d26aAEb94e71e3929;
    // Protocol Core - RoyaltyPolicyLAP
    address internal royaltyPolicyLAPAddr = 0x4074CEC2B3427f983D14d0C5E962a06B7162Ab92;
    // Protocol Core - RoyaltyModule
    address internal royaltyModuleAddr = 0x3C27b2D7d30131D4b58C3584FD7c86e3358744de;
    // Protocol Core - SUSD
    address internal susdAddr = 0x91f6F05B08c16769d3c85867548615d270C42fC7;

    IPAssetRegistry public ipAssetRegistry;
    LicensingModule public licensingModule;
    LicenseRegistry public licenseRegistry;
    LicenseToken public licenseToken;
    RoyaltyWorkflows public royaltyWorkflows;
    LicenseAttachmentWorkflows public licenseAttachmentWorkflows;
    RoyaltyModule public royaltyModule;
    PILicenseTemplate public pilTemplate;

    SimpleNFT public simpleNft;
    SUSD public susd;

    function setUp() public {
        ipAssetRegistry = IPAssetRegistry(ipAssetRegistryAddr);
        licensingModule = LicensingModule(licensingModuleAddr);
        licenseRegistry = LicenseRegistry(licenseRegistryAddr);
        licenseToken = LicenseToken(licenseTokenAddr);
        royaltyWorkflows = RoyaltyWorkflows(royaltyWorkflowsAddr);
        licenseAttachmentWorkflows = LicenseAttachmentWorkflows(licenseAttachmentWorkflowsAddr);
        pilTemplate = PILicenseTemplate(pilTemplateAddr);
        royaltyModule = RoyaltyModule(royaltyModuleAddr);

        // MAKE SURE TO LOOK BACK AT THIS IF IT SHOULD BE DEPLOYED OR NOT
        simpleNft = new SimpleNFT("Simple IP NFT", "SIM");
        susd = SUSD(susdAddr);

        vm.label(address(ipAssetRegistryAddr), "IPAssetRegistry");
        vm.label(address(licensingModuleAddr), "LicensingModule");
        vm.label(address(licenseRegistryAddr), "LicenseRegistry");
        vm.label(address(licenseTokenAddr), "LicenseToken");
        vm.label(address(pilTemplateAddr), "PILicenseTemplate");
        vm.label(address(royaltyWorkflowsAddr), "RoyaltyWorkflows");
        vm.label(address(royaltyModuleAddr), "RoyaltyModule");
        vm.label(address(susdAddr), "SUSD");
        vm.label(address(licenseAttachmentWorkflowsAddr), "LicenseAttachmentWorkflows");
        vm.label(address(simpleNft), "SimpleNFT");
        vm.label(address(0x000000006551c19487814612e58FE06813775758), "ERC6551Registry");
    }

    function test_royaltyIp() public {
        // setup this contract with funds to pay the child
        susd.mint(address(this), 100);
        susd.approve(address(royaltyModule), 10);
        IpRoyaltyVault ancestorIpRoyaltyVault = IpRoyaltyVault(royaltyModule.ipRoyaltyVaults(ancestorIpId));

        // transfer all ancestor royalties tokens to the claimer of the ancestor IP
        vm.prank(ancestorIpId);
        ancestorIpRoyaltyVault.transfer(address(this), ancestorIpRoyaltyVault.totalSupply());

        // this contract mints to alice
        uint256 ancestorTokenId = simpleNft.mint(alice);
        address ancestorIpId = ipAssetRegistry.register(block.chainid, address(simpleNft), ancestorTokenId);

        uint256 licenseTermsId = pilTemplate.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 0,
                commercialRevShare: 10 * 10 ** 6, // 10%
                royaltyPolicy: royaltyPolicyLAPAddr,
                currencyToken: address(susd)
            })
        );

        vm.prank(alice);
        licensingModule.attachLicenseTerms(ancestorIpId, pilTemplateAddr, licenseTermsId);

        // Then, mint a License Token from the attached license terms.
        // Note that the License Token is minted to the ltRecipient.
        vm.prank(bob);
        uint256 licenseTokenId = licensingModule.mintLicenseTokens({
            licensorIpId: ancestorIpId,
            licenseTemplate: pilTemplateAddr,
            licenseTermsId: licenseTermsId,
            amount: 1,
            receiver: bob,
            royaltyContext: "" // for PIL, royaltyContext is empty string
        });

        // this contract mints to bob
        uint256 childTokenId = simpleNft.mint(bob);
        address childIpId = ipAssetRegistry.register(block.chainid, address(simpleNft), childTokenId);

        uint256[] memory licenseTokenIds = new uint256[](1);
        licenseTokenIds[0] = licenseTokenId;

        vm.prank(bob);
        licensingModule.registerDerivativeWithLicenseTokens({
            childIpId: childIpId,
            licenseTokenIds: licenseTokenIds,
            royaltyContext: "" // empty for PIL
        });

        // now that it is derivative, we must give bob's ip Asset 10 susd for this example
        // need to use payRoyaltyOnBehalf
        //
        // you have to approve the royalty module to spend on your behalf
        royaltyModule.payRoyaltyOnBehalf(childIpId, address(0), address(susd), 10);

        // now that child has been paid, parent must claim
        IRoyaltyWorkflows.RoyaltyClaimDetails[] memory claimDetails = new IRoyaltyWorkflows.RoyaltyClaimDetails[](1);
        claimDetails[0] = IRoyaltyWorkflows.RoyaltyClaimDetails({
            childIpId: childIpId,
            royaltyPolicy: royaltyPolicyLAPAddr,
            currencyToken: address(susd),
            amount: 1
        });
        (uint256 snapshotId, uint256[] memory amountsClaimed) = royaltyWorkflows
            .transferToVaultAndSnapshotAndClaimByTokenBatch({
                ancestorIpId: ancestorIpId,
                claimer: ancestorIpId,
                royaltyClaimDetails: claimDetails
            });

        assertEq(amountsClaimed[0], 1);
        assertEq(susd.balanceOf(ancestorIpId), 1);
    }
}
