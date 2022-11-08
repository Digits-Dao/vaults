import { ethers, network } from "hardhat";
import { ManagedVaultFactory, ManagedVault, RedemptionHelper, IERC20 } from "../typechain-types";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { constants } from "ethers";
import { getBigNumber } from "../utils";

describe("ManagedVaultFactory", function () {
    let deployer: SignerWithAddress;
    let manager: SignerWithAddress;
    let redemptionHelper: SignerWithAddress;
    let alice: SignerWithAddress;
    let ManagedVaultFactory: ManagedVaultFactory;
    let ManagedVault: ManagedVault;
    let RedemptionHelper: RedemptionHelper;
    let Dai: IERC20;
    let snapshotId: string;
    const TOKEN_NAME = "TOKEN";
    const TOKEN_SYMBOL = "TKN";
    const TOKEN_AMOUNT = getBigNumber(10_000);
    const DAI_WHALE = "0xF977814e90dA44bFA03b6295A0616a897441aceC";
    const DAI = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
    const FIRST_CREATED_VAULT_ADDRESS = "0xe5B6b170AB9a28C516b375465D11D77683A26550";
    const FIRST_CREATED_HELPER_ADDRESS = "0xa5875EdD032eFbe7773084ae23C588daC243bc01";

    before(async () => {
        [deployer, manager, alice] = await ethers.getSigners();

        Dai = await ethers.getContractAt(
            "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", DAI) as IERC20;

        // send dai to alice
        const daiWhale = await ethers.getImpersonatedSigner(DAI_WHALE);
        await Dai.connect(daiWhale).transfer(alice.address, TOKEN_AMOUNT)

        const managedVaultFactory = await ethers.getContractFactory("ManagedVault");
        ManagedVault = (await managedVaultFactory.deploy()) as ManagedVault;

        const redemptionHelperFactory = await ethers.getContractFactory("RedemptionHelper");
        RedemptionHelper = (await redemptionHelperFactory.deploy()) as RedemptionHelper;

        const managedVaultFactoryFactory = await ethers.getContractFactory("ManagedVaultFactory");
        ManagedVaultFactory = (await managedVaultFactoryFactory.deploy(ManagedVault.address, RedemptionHelper.address)) as ManagedVaultFactory;

        snapshotId = await ethers.provider.send("evm_snapshot", []);
    });

    afterEach(async () => {
        await network.provider.send("evm_revert", [snapshotId]);
        snapshotId = await ethers.provider.send("evm_snapshot", []);
    });

    describe("createVault", () => {
        it("should create new contracts properly", async function () {
            let vaultsLengthBefore = (await ManagedVaultFactory.getVaults()).length;
            await ManagedVaultFactory.createVault(manager.address, TOKEN_NAME, TOKEN_SYMBOL);
            let vaults = await ManagedVaultFactory.getVaults();

            expect(vaultsLengthBefore).to.be.equal(0);
            expect(vaults.length).to.be.equal(1);

            let vault = await ethers.getContractAt(
                "ManagedVault", vaults[0]) as ManagedVault;

            expect(await vault.name()).to.be.equal(TOKEN_NAME);
            expect(await vault.symbol()).to.be.equal(TOKEN_SYMBOL);
            expect(await vault.admin()).to.be.equal(deployer.address);
            expect(await vault.owner()).to.be.equal(manager.address);
            expect(await vault.allowlist(await vault.redemptionHelper())).to.be.equal(true);

            let helper = await ethers.getContractAt(
                "RedemptionHelper", await vault.redemptionHelper()) as RedemptionHelper;
            expect(await helper.admin()).to.be.equal(deployer.address);
            expect(await helper.owner()).to.be.equal(manager.address);
        });

        it("should create new vaults each time", async function () {
            let vaultsLengthBefore = (await ManagedVaultFactory.getVaults()).length;
            await ManagedVaultFactory.createVault(manager.address, TOKEN_NAME, TOKEN_SYMBOL);
            await ManagedVaultFactory.createVault(manager.address, TOKEN_NAME, TOKEN_SYMBOL);
            let vaults = await ManagedVaultFactory.getVaults();

            expect(vaultsLengthBefore).to.be.equal(0);
            expect(vaults.length).to.be.equal(2);
            expect(vaults[0]).not.to.be.equal(vaults[1]);

            let vaultOne = await ethers.getContractAt(
                "ManagedVault", vaults[0]) as ManagedVault;
            let vaultTwo = await ethers.getContractAt(
                "ManagedVault", vaults[1]) as ManagedVault;

            expect(await vaultOne.redemptionHelper()).not.to.be.equal(await vaultTwo.redemptionHelper());
        });

        it("should create inactive vaults", async function () {
            await ManagedVaultFactory.createVault(manager.address, TOKEN_NAME, TOKEN_SYMBOL);
            let vaults = await ManagedVaultFactory.getVaults();

            expect(vaults.length).to.be.equal(1);
            expect(await ManagedVaultFactory.vaultExists(vaults[0])).to.be.equal(true);
            expect(await ManagedVaultFactory.vaultActive(vaults[0])).to.be.equal(false);
        });

        it("should emit proper event", async function () {
            let action = ManagedVaultFactory.createVault(manager.address, TOKEN_NAME, TOKEN_SYMBOL);
            await expect(action).to.emit(ManagedVaultFactory, "VaultCreated").withArgs(FIRST_CREATED_VAULT_ADDRESS, FIRST_CREATED_HELPER_ADDRESS, manager.address, TOKEN_NAME, TOKEN_SYMBOL);
        });

        it("should be callable only by owner", async function () {
            let action = ManagedVaultFactory.connect(alice).createVault(manager.address, TOKEN_NAME, TOKEN_SYMBOL);
            await expect(action).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });

    describe("changeManagedVaultImpl", () => {
        it("should not allow address zero", async function () {
            let action = ManagedVaultFactory.changeManagedVaultImpl(constants.AddressZero);
            await expect(action).to.be.reverted;
        });

        it("should emit proper event", async function () {
            let action = ManagedVaultFactory.changeManagedVaultImpl(alice.address);
            await expect(action).to.emit(ManagedVaultFactory, "ManagedVaultImplChanged").withArgs(ManagedVault.address, alice.address);
        });

        it("should be callable only by owner", async function () {
            let action = ManagedVaultFactory.connect(alice).changeManagedVaultImpl(alice.address);
            await expect(action).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });

    describe("changeRedemptionHelperImpl", () => {
        it("should not allow address zero", async function () {
            let action = ManagedVaultFactory.changeRedemptionHelperImpl(constants.AddressZero);
            await expect(action).to.be.reverted;
        });

        it("should emit proper event", async function () {
            let action = ManagedVaultFactory.changeRedemptionHelperImpl(alice.address);
            await expect(action).to.emit(ManagedVaultFactory, "RedemptionHelperImplChanged").withArgs(RedemptionHelper.address, alice.address);
        });

        it("should be callable only by owner", async function () {
            let action = ManagedVaultFactory.connect(alice).changeRedemptionHelperImpl(alice.address);
            await expect(action).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });

    describe("changeState", () => {
        beforeEach("createVault", async function () {
            await ManagedVaultFactory.createVault(manager.address, TOKEN_NAME, TOKEN_SYMBOL);
        });

        it("should not allow same state", async function () {
            let beforeVaultActiveState = await ManagedVaultFactory.vaultActive(FIRST_CREATED_VAULT_ADDRESS);
            let action = ManagedVaultFactory.changeState(FIRST_CREATED_VAULT_ADDRESS, beforeVaultActiveState);
            await expect(action).to.be.reverted;
        });

        it("should emit proper event", async function () {
            let beforeVaultActiveState = await ManagedVaultFactory.vaultActive(FIRST_CREATED_VAULT_ADDRESS);
            let action = ManagedVaultFactory.changeState(FIRST_CREATED_VAULT_ADDRESS, true);
            await expect(action).to.emit(ManagedVaultFactory, "StateChanged").withArgs(FIRST_CREATED_VAULT_ADDRESS, true);
            let afterVaultActiveState = await ManagedVaultFactory.vaultActive(FIRST_CREATED_VAULT_ADDRESS);
            expect(beforeVaultActiveState).to.be.equal(false);
            expect(afterVaultActiveState).to.be.equal(true);
        });

        it("should be callable only by owner", async function () {
            let action = ManagedVaultFactory.connect(alice).changeState(FIRST_CREATED_VAULT_ADDRESS, true);
            await expect(action).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });
});