import { ethers, network } from "hardhat";
import { ManagedVaultFactory, ManagedVault, RedemptionHelper, IERC20 } from "../typechain-types";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { constants } from "ethers";
import { getBigNumber } from "../utils";
import * as helpers from "@nomicfoundation/hardhat-network-helpers";

describe("RedemptionHelper", function () {
    let deployer: SignerWithAddress;
    let manager: SignerWithAddress;
    let alice: SignerWithAddress;
    let bob: SignerWithAddress;
    let daiWhale: SignerWithAddress;
    let ManagedVaultFactory: ManagedVaultFactory;
    let ManagedVault: ManagedVault;
    let VaultImpl: ManagedVault;
    let HelperImpl: RedemptionHelper;
    let RedemptionHelper: RedemptionHelper;
    let Dai: IERC20;
    let snapshotId: string;
    const TOKEN_NAME = "TOKEN";
    const TOKEN_SYMBOL = "TKN";
    const TOKEN_AMOUNT = getBigNumber(10_000);
    const DAI_WHALE = "0xF977814e90dA44bFA03b6295A0616a897441aceC";
    const DAI = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
    const FIRST_CREATED_VAULT_ADDRESS = "0x2DD53CBC6A49F31127618914d03c0EbaD8dC8288";
    const FIRST_CREATED_HELPER_ADDRESS = "0xB489bFc842a631FA90C4A1c8967AB0A134b3C0e4";
    const DAY_IN_SECONDS = 60 * 60 * 24;
    const MAX_FEE = 1_000;

    before(async () => {
        [deployer, manager, alice, bob] = await ethers.getSigners();

        Dai = await ethers.getContractAt(
            "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", DAI) as IERC20;

        // send dai to alice and bob
        daiWhale = await ethers.getImpersonatedSigner(DAI_WHALE);
        await Dai.connect(daiWhale).transfer(alice.address, TOKEN_AMOUNT);
        await Dai.connect(daiWhale).transfer(bob.address, TOKEN_AMOUNT);

        const managedVaultFactory = await ethers.getContractFactory("ManagedVault");
        VaultImpl = (await managedVaultFactory.deploy()) as ManagedVault;

        const redemptionHelperFactory = await ethers.getContractFactory("RedemptionHelper");
        HelperImpl = (await redemptionHelperFactory.deploy()) as RedemptionHelper;

        const managedVaultFactoryFactory = await ethers.getContractFactory("ManagedVaultFactory");
        ManagedVaultFactory = (await managedVaultFactoryFactory.deploy(VaultImpl.address, HelperImpl.address)) as ManagedVaultFactory;

        await ManagedVaultFactory.createVault(manager.address, TOKEN_NAME, TOKEN_SYMBOL);
        let vaults = await ManagedVaultFactory.getVaults();
        ManagedVault = await ethers.getContractAt(
            "ManagedVault", vaults[0]) as ManagedVault;
        RedemptionHelper = await ethers.getContractAt(
            "RedemptionHelper", await ManagedVault.redemptionHelper()) as RedemptionHelper;

        await Dai.connect(alice).approve(ManagedVault.address, constants.MaxUint256);
        await ManagedVault.connect(alice).approve(RedemptionHelper.address, constants.MaxUint256);
        await Dai.connect(bob).approve(ManagedVault.address, constants.MaxUint256);
        await ManagedVault.connect(bob).approve(RedemptionHelper.address, constants.MaxUint256);
        await Dai.connect(manager).approve(RedemptionHelper.address, constants.MaxUint256);

        snapshotId = await ethers.provider.send("evm_snapshot", []);
    });

    async function _initilaize() {
        await ManagedVault.connect(manager).setTokenDepositState(DAI, true);
        await ManagedVault.connect(manager).setTokenMinimumDepositAmount(DAI, 100);
        var currentBlock = await ethers.provider.getBlockNumber();
        await ManagedVault.connect(manager).setPrices(currentBlock, 100, 1500, [DAI], [1]);
        await ManagedVault.connect(alice).depositToken(DAI, 1000);
        await ManagedVault.connect(bob).depositToken(DAI, 500);
        currentBlock = await ethers.provider.getBlockNumber();
        await ManagedVault.connect(manager).setPrices(currentBlock, 100, 1500, [DAI], [1]);
        await ManagedVault.connect(manager).mint(10);
        await RedemptionHelper.connect(manager).setRedemptionInterval(DAY_IN_SECONDS * 30);
        await RedemptionHelper.connect(manager).setPreparationTime(DAY_IN_SECONDS * 20);
        await RedemptionHelper.connect(manager).setRedemptionToken(DAI);
        await RedemptionHelper.connect(manager).initializeRedemptions(0, 0);

        expect(await ManagedVault.balanceOf(alice.address)).to.be.equal(10);
        expect(await ManagedVault.balanceOf(bob.address)).to.be.equal(5);

        await RedemptionHelper.connect(alice).register(10);
        await RedemptionHelper.connect(bob).register(5);

        expect(await ManagedVault.balanceOf(RedemptionHelper.address)).to.be.equal(15);
    }

    afterEach(async () => {
        await network.provider.send("evm_revert", [snapshotId]);
        snapshotId = await ethers.provider.send("evm_snapshot", []);
    });

    describe("initialize", () => {
        it("should not be initialized before calling", async function () {
            expect(await HelperImpl.owner()).to.be.equal(deployer.address);
            expect(await HelperImpl.vault()).to.be.equal(constants.AddressZero);
            expect(await HelperImpl.admin()).to.be.equal(constants.AddressZero);
        });

        it("should not allow zero addresses", async function () {
            const ownerZero = HelperImpl.initialize(constants.AddressZero, manager.address, VaultImpl.address);
            await expect(ownerZero).to.be.reverted;

            const adminZero = HelperImpl.initialize(deployer.address, constants.AddressZero, VaultImpl.address);
            await expect(adminZero).to.be.reverted;

            const vaultZero = HelperImpl.initialize(deployer.address, manager.address, constants.AddressZero);
            await expect(vaultZero).to.be.reverted;
        });

        it("should initialize properly", async function () {
            await HelperImpl.initialize(manager.address, deployer.address, VaultImpl.address);
            expect(await HelperImpl.owner()).to.be.equal(manager.address);
            expect(await HelperImpl.vault()).to.be.equal(VaultImpl.address);
            expect(await HelperImpl.admin()).to.be.equal(deployer.address);
        });

        it("should be callable only once", async function () {
            await HelperImpl.initialize(manager.address, deployer.address, VaultImpl.address);
            const action = HelperImpl.initialize(manager.address, deployer.address, VaultImpl.address);
            await expect(action).to.be.revertedWith("Initializable: contract is already initialized");
        });
    });

    describe("changeOwner", () => {
        beforeEach("initialize", async function () {
            await HelperImpl.initialize(manager.address, deployer.address, VaultImpl.address);
        });

        it("should not be callable by other than admin", async function () {
            const action = HelperImpl.connect(alice).changeOwner(alice.address);
            await expect(action).to.be.reverted;
        });

        it("should be callable by admin", async function () {
            await HelperImpl.changeOwner(alice.address);
            expect(await HelperImpl.owner()).to.be.equal(alice.address);
        });
    });

    describe("setRedemptionInterval", () => {
        beforeEach("initialize", async function () {
            await HelperImpl.initialize(manager.address, deployer.address, VaultImpl.address);
        });

        it("should not allow interval shorter than preparation time", async function () {
            await HelperImpl.connect(manager).setRedemptionInterval(DAY_IN_SECONDS * 30);
            await HelperImpl.connect(manager).setPreparationTime(DAY_IN_SECONDS * 10)
            let action = HelperImpl.connect(manager).setRedemptionInterval(DAY_IN_SECONDS * 5);
            await expect(action).to.be.reverted;
        });

        it("should emit proper event", async function () {
            let interval = DAY_IN_SECONDS * 30;
            let action = HelperImpl.connect(manager).setRedemptionInterval(interval);
            await expect(action).to.emit(HelperImpl, "RedemptionIntervalSet").withArgs(interval);
        });

        it("should be callable only by owner", async function () {
            let action = HelperImpl.connect(alice).setRedemptionInterval(DAY_IN_SECONDS * 30);
            await expect(action).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });

    describe("setPreparationTime", () => {
        beforeEach("initialize", async function () {
            await HelperImpl.initialize(manager.address, deployer.address, VaultImpl.address);
            await HelperImpl.connect(manager).setRedemptionInterval(DAY_IN_SECONDS * 30);
        });

        it("should not allow interval longer than interval time", async function () {
            let action = HelperImpl.connect(manager).setPreparationTime(DAY_IN_SECONDS * 90)
            await expect(action).to.be.reverted;
        });

        it("should emit proper event", async function () {
            let preparation = DAY_IN_SECONDS * 20;
            let action = HelperImpl.connect(manager).setPreparationTime(preparation);
            await expect(action).to.emit(HelperImpl, "PreparationTimeSet").withArgs(preparation);
        });

        it("should be callable only by owner", async function () {
            let action = HelperImpl.connect(alice).setPreparationTime(DAY_IN_SECONDS * 20);
            await expect(action).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });

    describe("setRedemptionToken", () => {
        beforeEach("initialize", async function () {
            await HelperImpl.initialize(manager.address, deployer.address, VaultImpl.address);
        });

        it("should not allow address zero", async function () {
            let action = HelperImpl.connect(manager).setRedemptionToken(constants.AddressZero)
            await expect(action).to.be.reverted;
        });

        it("should emit proper event", async function () {
            let action = HelperImpl.connect(manager).setRedemptionToken(DAI)
            await expect(action).to.emit(HelperImpl, "RedemptionTokenSet").withArgs(DAI);
        });

        it("should be callable only by owner", async function () {
            let action = HelperImpl.connect(alice).setRedemptionToken(DAI)
            await expect(action).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });

    describe("initializeRedemptions", () => {
        beforeEach("initialize", async function () {
            await HelperImpl.initialize(manager.address, deployer.address, VaultImpl.address);
        });

        it("should not allow uninitialized variables", async function () {
            let redemptionTimeZero = HelperImpl.connect(manager).initializeRedemptions(0, 0);
            await expect(redemptionTimeZero).to.be.reverted;

            await HelperImpl.connect(manager).setRedemptionInterval(DAY_IN_SECONDS * 30);
            let preparationTimeZero = HelperImpl.connect(manager).initializeRedemptions(0, 0);
            await expect(preparationTimeZero).to.be.reverted;

            await HelperImpl.connect(manager).setPreparationTime(DAY_IN_SECONDS * 20);
            let tokenZero = HelperImpl.connect(manager).initializeRedemptions(0, 0);
            await expect(tokenZero).to.be.reverted;

            await HelperImpl.connect(manager).setRedemptionToken(DAI);
            let allInitialized = HelperImpl.connect(manager).initializeRedemptions(0, 0);
            await expect(allInitialized).not.to.be.reverted;
        });

        it("should create proper redemption", async function () {
            await HelperImpl.connect(manager).setRedemptionInterval(DAY_IN_SECONDS * 30);
            await HelperImpl.connect(manager).setPreparationTime(DAY_IN_SECONDS * 20);
            await HelperImpl.connect(manager).setRedemptionToken(DAI);
            let action = HelperImpl.connect(manager).initializeRedemptions(0, 0);

            let latestBlockTime = await helpers.time.latest() + 1;
            let expectedTime = latestBlockTime + DAY_IN_SECONDS * 30;
            let expectedRegistrationTime = latestBlockTime + DAY_IN_SECONDS * 10;

            await expect(action).to.emit(HelperImpl, "NewRedemption").withArgs(0, expectedTime, expectedRegistrationTime, 0, DAI);

            let redemption = await HelperImpl.redemptions(0);
            expect(redemption.redemptionTime).to.be.equal(expectedTime);
            expect(redemption.registrationEndTime).to.be.equal(expectedRegistrationTime);
            expect(redemption.token).to.be.equal(DAI);
            expect(redemption.pending).to.be.equal(0);
            expect(redemption.price).to.be.equal(0);
            expect(redemption.fee).to.be.equal(0);
            expect(redemption.active).to.be.equal(false);
        });

        it("should create redemption with fee", async function () {
            await HelperImpl.connect(manager).setRedemptionInterval(DAY_IN_SECONDS * 30);
            await HelperImpl.connect(manager).setPreparationTime(DAY_IN_SECONDS * 20);
            await HelperImpl.connect(manager).setRedemptionToken(DAI);

            let action = HelperImpl.connect(manager).initializeRedemptions(0, MAX_FEE);

            let latestBlockTime = await helpers.time.latest() + 1;
            let expectedTime = latestBlockTime + DAY_IN_SECONDS * 30;
            let expectedRegistrationTime = latestBlockTime + DAY_IN_SECONDS * 10;

            await expect(action).to.emit(HelperImpl, "NewRedemption").withArgs(0, expectedTime, expectedRegistrationTime, MAX_FEE, DAI);

            let redemption = await HelperImpl.redemptions(0);
            expect(redemption.redemptionTime).to.be.equal(expectedTime);
            expect(redemption.registrationEndTime).to.be.equal(expectedRegistrationTime);
            expect(redemption.token).to.be.equal(DAI);
            expect(redemption.pending).to.be.equal(0);
            expect(redemption.price).to.be.equal(0);
            expect(redemption.fee).to.be.equal(MAX_FEE);
            expect(redemption.active).to.be.equal(false);
        });

        it("should not create redemption with too high fee", async function () {
            await HelperImpl.connect(manager).setRedemptionInterval(DAY_IN_SECONDS * 30);
            await HelperImpl.connect(manager).setPreparationTime(DAY_IN_SECONDS * 20);
            await HelperImpl.connect(manager).setRedemptionToken(DAI);
            let action = HelperImpl.connect(manager).initializeRedemptions(0, MAX_FEE + 1);
            await expect(action).to.be.reverted;
        });

        it("should create redemption with exact date", async function () {
            await HelperImpl.connect(manager).setRedemptionInterval(DAY_IN_SECONDS * 30);
            await HelperImpl.connect(manager).setPreparationTime(DAY_IN_SECONDS * 20);
            await HelperImpl.connect(manager).setRedemptionToken(DAI);

            let latestBlockTime = await helpers.time.latest() + 1;

            let action = HelperImpl.connect(manager).initializeRedemptions(latestBlockTime + DAY_IN_SECONDS * 60, MAX_FEE);

            let expectedTime = latestBlockTime + DAY_IN_SECONDS * 60;
            let expectedRegistrationTime = latestBlockTime + DAY_IN_SECONDS * 40;

            await expect(action).to.emit(HelperImpl, "NewRedemption").withArgs(0, expectedTime, expectedRegistrationTime, MAX_FEE, DAI);

            let redemption = await HelperImpl.redemptions(0);
            expect(redemption.redemptionTime).to.be.equal(expectedTime);
            expect(redemption.registrationEndTime).to.be.equal(expectedRegistrationTime);
            expect(redemption.token).to.be.equal(DAI);
            expect(redemption.pending).to.be.equal(0);
            expect(redemption.price).to.be.equal(0);
            expect(redemption.fee).to.be.equal(MAX_FEE);
            expect(redemption.active).to.be.equal(false);
        });

        it("should not create redemption with wrong exact date", async function () {
            await HelperImpl.connect(manager).setRedemptionInterval(DAY_IN_SECONDS * 30);
            await HelperImpl.connect(manager).setPreparationTime(DAY_IN_SECONDS * 20);
            await HelperImpl.connect(manager).setRedemptionToken(DAI);

            let latestBlockTime = await helpers.time.latest();

            let pastExactDate = HelperImpl.connect(manager).initializeRedemptions(latestBlockTime - 1000, MAX_FEE);
            await expect(pastExactDate).to.be.reverted;

            let ExactDateTooClose = HelperImpl.connect(manager).initializeRedemptions(latestBlockTime + DAY_IN_SECONDS * 5, MAX_FEE);
            await expect(ExactDateTooClose).to.be.reverted;
        });

        it("should be callable only once", async function () {
            await HelperImpl.connect(manager).setRedemptionInterval(DAY_IN_SECONDS * 30);
            await HelperImpl.connect(manager).setPreparationTime(DAY_IN_SECONDS * 20);
            await HelperImpl.connect(manager).setRedemptionToken(DAI);
            await HelperImpl.connect(manager).initializeRedemptions(0, MAX_FEE);
            let action = HelperImpl.connect(manager).initializeRedemptions(0, MAX_FEE);
            await expect(action).to.be.revertedWith("Redemptions are already active");
        });

        it("should be callable only by owner", async function () {
            let action = HelperImpl.connect(alice).initializeRedemptions(0, 0)
            await expect(action).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });

    describe("activateRedemption", () => {
        beforeEach("initialize", _initilaize);

        it("should not activate redemption before time", async function () {
            let action = RedemptionHelper.connect(manager).activateRedemption(0, 0);
            await expect(action).to.be.revertedWith("Redemption time in the future");
        });

        it("should not activate redemption without recently updated price", async function () {
            let blockNumber = await helpers.time.latestBlock();
            let setPriceBlockUpdate = await ManagedVault.setPriceBlockNumber();
            let redemptionTime = await RedemptionHelper.getNextRedemptionTime();
            await helpers.time.setNextBlockTimestamp(redemptionTime.add(1000));
            helpers.mineUpTo(blockNumber + 5000);
            let latestBlock = await helpers.time.latestBlock();
            let action = RedemptionHelper.connect(manager).activateRedemption(0, 0);
            await expect(action).to.be.revertedWith("Price not set within 5000 blocks");
            expect(latestBlock + 5000).is.greaterThanOrEqual(setPriceBlockUpdate);
        });

        it("should not activate redemption without prepared redemption tokens", async function () {
            let redemptionTime = await RedemptionHelper.getNextRedemptionTime();
            await helpers.time.setNextBlockTimestamp(redemptionTime.add(1000));
            await ManagedVault.connect(manager).setPrices(await helpers.time.latestBlock(), 200, 1500, [DAI], [1]);
            let action = RedemptionHelper.connect(manager).activateRedemption(0, 0);
            await expect(action).to.be.revertedWith("Dai/insufficient-balance");
        });

        it("should activate redemption properly", async function () {
            await Dai.connect(daiWhale).transfer(manager.address, getBigNumber(1500));
            let redemptionTime = await RedemptionHelper.getNextRedemptionTime();
            await helpers.time.setNextBlockTimestamp(redemptionTime.add(1000));
            await ManagedVault.connect(manager).setPrices(await helpers.time.latestBlock(), 200, 1500, [DAI], [1]);
            let action = RedemptionHelper.connect(manager).activateRedemption(0, 0);

            let latestBlockTime = await helpers.time.latest() + 1;
            let expectedTime = latestBlockTime + DAY_IN_SECONDS * 30;
            let expectedRegistrationTime = latestBlockTime + DAY_IN_SECONDS * 10;

            await expect(action).to.emit(RedemptionHelper, "RedemptionActivated").withArgs(0, 200, DAI)
                .and.to.emit(RedemptionHelper, "NewRedemption").withArgs(1, expectedTime, expectedRegistrationTime, 0, DAI);

            let redemption = await RedemptionHelper.redemptions(0);
            expect(redemption.token).to.be.equal(DAI);
            expect(redemption.pending).to.be.equal(15);
            expect(redemption.price).to.be.equal(200);
            expect(redemption.fee).to.be.equal(0);
            expect(redemption.active).to.be.equal(true);

            let newRedemption = await RedemptionHelper.redemptions(1);
            expect(newRedemption.redemptionTime).to.be.equal(expectedTime);
            expect(newRedemption.registrationEndTime).to.be.equal(expectedRegistrationTime);
            expect(newRedemption.token).to.be.equal(DAI);
            expect(newRedemption.pending).to.be.equal(0);
            expect(newRedemption.price).to.be.equal(0);
            expect(newRedemption.fee).to.be.equal(0);
            expect(newRedemption.active).to.be.equal(false);

            expect(await RedemptionHelper.userClaims(alice.address, 0)).to.be.equal(10);
            expect(await RedemptionHelper.userClaims(bob.address, 0)).to.be.equal(5);
        });

        it("should create redemption with exact date", async function () {
            await Dai.connect(daiWhale).transfer(manager.address, getBigNumber(1500));
            let redemptionTime = await RedemptionHelper.getNextRedemptionTime();
            await helpers.time.setNextBlockTimestamp(redemptionTime.add(1000));
            await ManagedVault.connect(manager).setPrices(await helpers.time.latestBlock(), 200, 1500, [DAI], [1]);
            let latestBlockTime = await helpers.time.latest() + 1;
            let action = RedemptionHelper.connect(manager).activateRedemption(latestBlockTime + DAY_IN_SECONDS * 60, MAX_FEE);

            let expectedTime = latestBlockTime + DAY_IN_SECONDS * 60;
            let expectedRegistrationTime = latestBlockTime + DAY_IN_SECONDS * 40;

            await expect(action).to.emit(RedemptionHelper, "RedemptionActivated").withArgs(0, 200, DAI)
                .and.to.emit(RedemptionHelper, "NewRedemption").withArgs(1, expectedTime, expectedRegistrationTime, MAX_FEE, DAI);

            let newRedemption = await RedemptionHelper.redemptions(1);
            expect(newRedemption.redemptionTime).to.be.equal(expectedTime);
            expect(newRedemption.registrationEndTime).to.be.equal(expectedRegistrationTime);
            expect(newRedemption.token).to.be.equal(DAI);
            expect(newRedemption.pending).to.be.equal(0);
            expect(newRedemption.price).to.be.equal(0);
            expect(newRedemption.fee).to.be.equal(MAX_FEE);
            expect(newRedemption.active).to.be.equal(false);

            expect(await RedemptionHelper.userClaims(alice.address, 0)).to.be.equal(10);
            expect(await RedemptionHelper.userClaims(bob.address, 0)).to.be.equal(5);
        });

        it("should not create redemption with wrong exact date", async function () {
            await Dai.connect(daiWhale).transfer(manager.address, getBigNumber(1500));
            let redemptionTime = await RedemptionHelper.getNextRedemptionTime();
            await helpers.time.setNextBlockTimestamp(redemptionTime.add(1000));
            await ManagedVault.connect(manager).setPrices(await helpers.time.latestBlock(), 200, 1500, [DAI], [1]);
            let latestBlockTime = await helpers.time.latest();

            let pastExactDate = RedemptionHelper.connect(manager).activateRedemption(latestBlockTime - 1000, MAX_FEE);
            await expect(pastExactDate).to.be.reverted;

            let ExactDateTooClose = RedemptionHelper.connect(manager).activateRedemption(latestBlockTime + DAY_IN_SECONDS * 5, MAX_FEE);
            await expect(ExactDateTooClose).to.be.reverted;
        });

        it("should not create new redemption with too high fee", async function () {
            await Dai.connect(daiWhale).transfer(manager.address, getBigNumber(1500));
            let redemptionTime = await RedemptionHelper.getNextRedemptionTime();
            await helpers.time.setNextBlockTimestamp(redemptionTime.add(1000));
            await ManagedVault.connect(manager).setPrices(await helpers.time.latestBlock(), 200, 1500, [DAI], [1]);

            let action = HelperImpl.connect(manager).activateRedemption(0, MAX_FEE + 1);
            await expect(action).to.be.reverted;
        });

        it("should be callable only by owner", async function () {
            let redemptionTime = await RedemptionHelper.getNextRedemptionTime();
            await helpers.time.setNextBlockTimestamp(redemptionTime.add(1000));
            await ManagedVault.connect(manager).setPrices(await helpers.time.latestBlock(), 200, 1500, [DAI], [1]);

            let action = HelperImpl.connect(alice).activateRedemption(0, MAX_FEE + 1);
            await expect(action).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });

    describe("register", () => {
        beforeEach("initialize", _initilaize);

        it("should not register after registration time", async function () {
            let registrationTime = (await RedemptionHelper.redemptions(0)).registrationEndTime;
            await helpers.time.setNextBlockTimestamp(registrationTime.add(100));
            await ManagedVault.connect(manager).setPrices(await helpers.time.latestBlock(), 200, 1500, [DAI], [1]);

            let action = RedemptionHelper.connect(bob).register(5);
            await expect(action).to.be.revertedWith("Registration time ended");
        });

        it("should not register with too few vault tokens", async function () {
            let action = RedemptionHelper.connect(bob).register(getBigNumber(TOKEN_AMOUNT));
            await expect(action).to.be.revertedWith("Too few vault tokens");
        });

        it("should register properly", async function () {
            await ManagedVault.connect(bob).depositToken(DAI, TOKEN_AMOUNT.sub(500));
            let currentBlock = await ethers.provider.getBlockNumber();
            await ManagedVault.connect(manager).setPrices(currentBlock, 100, 1500, [DAI], [1]);
            await ManagedVault.connect(manager).mint(10);
            await RedemptionHelper.connect(bob).register(95);

            expect(await RedemptionHelper.userClaims(bob.address, 0)).to.be.equal(100);
            expect((await RedemptionHelper.redemptions(0)).pending).to.be.equal(110);
        });
    });

    describe("unregister", () => {
        beforeEach("initialize", _initilaize);

        it("should not unregister after registration time", async function () {
            let registrationTime = (await RedemptionHelper.redemptions(0)).registrationEndTime;
            await helpers.time.setNextBlockTimestamp(registrationTime.add(100));
            await ManagedVault.connect(manager).setPrices(await helpers.time.latestBlock(), 200, 1500, [DAI], [1]);

            let action = RedemptionHelper.connect(bob).unregister(5);
            await expect(action).to.be.revertedWith("Registration time ended");
        });

        it("should not unregister with too few registered vault tokens", async function () {
            let action = RedemptionHelper.connect(bob).unregister(10);
            await expect(action).to.be.revertedWith("Too few registered tokens");
        });

        it("should unregister properly", async function () {
            await RedemptionHelper.connect(bob).unregister(5);

            expect(await RedemptionHelper.userClaims(bob.address, 0)).to.be.equal(0);
            expect((await RedemptionHelper.redemptions(0)).pending).to.be.equal(10);
        });
    });

    describe("redeem", () => {
        beforeEach("initialize", _initilaize);

        it("should not redeem inactive redemption", async function () {
            let action = RedemptionHelper.connect(alice).redeem([0]);
            await expect(action).to.be.revertedWith("Redemption is not active yet");
        });

        it("should not redeem not having registered tokens", async function () {
            await Dai.connect(daiWhale).transfer(manager.address, getBigNumber(1500));
            let redemptionTime = await RedemptionHelper.getNextRedemptionTime();
            await helpers.time.setNextBlockTimestamp(redemptionTime.add(1000));
            await ManagedVault.connect(manager).setPrices(await helpers.time.latestBlock(), 200, 1500, [DAI], [1]);
            await RedemptionHelper.connect(manager).activateRedemption(0, 0);

            let action = RedemptionHelper.connect(daiWhale).redeem([0]);
            await expect(action).to.be.revertedWith("No tokens registered");
        });

        it("should redeem properly", async function () {
            await Dai.connect(daiWhale).transfer(manager.address, getBigNumber(1500));
            let redemptionTime = await RedemptionHelper.getNextRedemptionTime();
            await helpers.time.setNextBlockTimestamp(redemptionTime.add(1000));
            await ManagedVault.connect(manager).setPrices(await helpers.time.latestBlock(), 200, 1500, [DAI], [1]);
            await RedemptionHelper.connect(manager).activateRedemption(0, 0);

            let daiBalance = await Dai.balanceOf(alice.address);

            let action = RedemptionHelper.connect(alice).redeem([0]);
            await expect(action).to.emit(RedemptionHelper, "Reedemed").withArgs(0, alice.address, 2000, DAI);
            expect(await Dai.balanceOf(alice.address)).to.be.equal(daiBalance.add(2000));
        });
    });
});