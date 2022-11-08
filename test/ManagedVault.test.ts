import { ethers, network } from "hardhat";
import { ManagedVault, IERC20 } from "../typechain-types";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { constants } from "ethers";
import { getBigNumber } from "../utils";

describe("ManagedVault", function () {
    let deployer: SignerWithAddress;
    let manager: SignerWithAddress;
    let redemptionHelper: SignerWithAddress;
    let alice: SignerWithAddress;
    let ManagedVault: ManagedVault;
    let Dai: IERC20;
    let snapshotId: string;
    const TOKEN_NAME = "TOKEN";
    const TOKEN_SYMBOL = "TKN";
    const TOKEN_AMOUNT = getBigNumber(10_000);
    const DAI_WHALE = "0xF977814e90dA44bFA03b6295A0616a897441aceC";
    const DAI = "0x6B175474E89094C44Da98b954EedeAC495271d0F";

    before(async () => {
        [deployer, manager, redemptionHelper, alice] = await ethers.getSigners();

        Dai = await ethers.getContractAt(
            "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", DAI) as IERC20;

        // send dai to alice
        const daiWhale = await ethers.getImpersonatedSigner(DAI_WHALE);
        await Dai.connect(daiWhale).transfer(alice.address, TOKEN_AMOUNT)

        const managedVaultFactory = await ethers.getContractFactory("ManagedVault");
        ManagedVault = (await managedVaultFactory.deploy()) as ManagedVault;
        await Dai.connect(alice).approve(ManagedVault.address, constants.MaxUint256);
        await ManagedVault.connect(alice).approve(redemptionHelper.address, constants.MaxUint256);
        await ManagedVault.connect(alice).approve(deployer.address, constants.MaxUint256);

        snapshotId = await ethers.provider.send("evm_snapshot", []);
    });

    afterEach(async () => {
        await network.provider.send("evm_revert", [snapshotId]);
        snapshotId = await ethers.provider.send("evm_snapshot", []);
    });

    async function _initilaize() {
        await ManagedVault.initialize(manager.address, deployer.address, redemptionHelper.address, TOKEN_NAME, TOKEN_SYMBOL);
        await ManagedVault.connect(manager).setTokenDepositState(DAI, true);
        await ManagedVault.connect(manager).setTokenMinimumDepositAmount(DAI, 100);
        var currentBlock = await ethers.provider.getBlockNumber();
        await ManagedVault.connect(manager).setPrices(currentBlock, 100, 1385, [DAI], [1]);
        await ManagedVault.connect(alice).depositToken(DAI, 1000);
        currentBlock = await ethers.provider.getBlockNumber();
        await ManagedVault.connect(manager).setPrices(currentBlock, 100, 1385, [DAI], [1]);
        await ManagedVault.connect(manager).mint(10);
    }

    describe("initialize", () => {
        it("should not be initialized before calling", async function () {
            expect(await ManagedVault.name()).to.be.equal("");
            expect(await ManagedVault.symbol()).to.be.equal("");
            expect(await ManagedVault.admin()).to.be.equal(constants.AddressZero);
            expect(await ManagedVault.redemptionHelper()).to.be.equal(constants.AddressZero);
        });

        it("should initialize properly", async function () {
            await ManagedVault.initialize(manager.address, deployer.address, redemptionHelper.address, TOKEN_NAME, TOKEN_SYMBOL);
            expect(await ManagedVault.name()).to.be.equal(TOKEN_NAME);
            expect(await ManagedVault.symbol()).to.be.equal(TOKEN_SYMBOL);
            expect(await ManagedVault.admin()).to.be.equal(deployer.address);
            expect(await ManagedVault.owner()).to.be.equal(manager.address);
            expect(await ManagedVault.redemptionHelper()).to.be.equal(redemptionHelper.address);
            expect(await ManagedVault.allowlist(redemptionHelper.address)).to.be.equal(true);
        });

        it("should be callable only once", async function () {
            await ManagedVault.initialize(manager.address, deployer.address, redemptionHelper.address, TOKEN_NAME, TOKEN_SYMBOL);
            const action = ManagedVault.initialize(manager.address, deployer.address, redemptionHelper.address, TOKEN_NAME, TOKEN_SYMBOL);
            await expect(action).to.be.revertedWith("Initializable: contract is already initialized");
        });
    });

    describe("transfer", () => {
        beforeEach("initialize", _initilaize);

        it("should not be callable by address not on allowlist", async function () {
            const action = ManagedVault.connect(alice).transfer(deployer.address, 10);
            await expect(action).to.be.revertedWith("Transfer not allowed");
        });

        it("should be callable by address on allowlist", async function () {
            await ManagedVault.changeAllowlist(alice.address, true);
            await ManagedVault.connect(alice).transfer(deployer.address, 10);
            expect(await ManagedVault.balanceOf(deployer.address)).to.be.equal(10);
        });
    });

    describe("transferFrom", () => {
        beforeEach("initialize", _initilaize);

        it("should not be callable by address not on allowlist", async function () {
            const action = ManagedVault.connect(deployer).transferFrom(alice.address, redemptionHelper.address, 10);
            await expect(action).to.be.revertedWith("Transfer not allowed");
        });

        it("should be callable by address on allowlist", async function () {
            await ManagedVault.connect(redemptionHelper).transferFrom(alice.address, deployer.address, 10);
            expect(await ManagedVault.balanceOf(deployer.address)).to.be.equal(10);
        });
    });

    describe("changeOwner", () => {
        beforeEach("initialize", _initilaize);

        it("should not be callable by other than admin", async function () {
            const action = ManagedVault.connect(manager).changeOwner(alice.address);
            await expect(action).to.be.reverted;
        });

        it("should be callable by admin", async function () {
            await ManagedVault.changeOwner(alice.address);
            expect(await ManagedVault.owner()).to.be.equal(alice.address);
        });
    });

    describe("changeAllowlist", () => {
        beforeEach("initialize", _initilaize);

        it("should not be callable by other than admin", async function () {
            const action = ManagedVault.connect(manager).changeAllowlist(alice.address, true);
            await expect(action).to.be.reverted;
        });

        it("should be callable by admin", async function () {
            await ManagedVault.changeAllowlist(alice.address, true);
            expect(await ManagedVault.allowlist(alice.address)).to.be.equal(true);
        });
    });

    describe("burn", () => {
        beforeEach("initialize", async function () {
            await _initilaize();
            await ManagedVault.connect(redemptionHelper).transferFrom(alice.address, redemptionHelper.address, 10);
        });

        it("should not be callable by others than redemptionHelper", async function () {
            const action = ManagedVault.connect(alice).burn(10);
            await expect(action).to.be.reverted;
        });

        it("should be callable by redemptionHelper", async function () {
            const action = ManagedVault.connect(redemptionHelper).burn(10);
            await expect(action).to.emit(ManagedVault, "Transfer").withArgs(redemptionHelper.address, constants.AddressZero, 10);
            expect(await ManagedVault.totalSupply()).to.be.equal(0);
        });
    });
});