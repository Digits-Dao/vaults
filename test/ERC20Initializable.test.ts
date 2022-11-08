import { ethers, network } from "hardhat";
import { ERC20Initializable } from "../typechain-types";
import { expect } from "chai";

describe("ERC20Initializable", function () {
    let ERC20Initializable: ERC20Initializable;
    let snapshotId: string;
    const TOKEN_NAME = "TOKEN";
    const TOKEN_SYMBOL = "TKN";

    before(async () => {
        const erc20Factory = await ethers.getContractFactory("ERC20Initializable");
        ERC20Initializable = (await erc20Factory.deploy()) as ERC20Initializable;
        snapshotId = await ethers.provider.send("evm_snapshot", []);
    });

    afterEach(async () => {
        await network.provider.send("evm_revert", [snapshotId]);
        snapshotId = await ethers.provider.send("evm_snapshot", []);
    });

    describe("__ERC20_init", () => {
        it("should not be initialized before calling", async function () {
            expect(await ERC20Initializable.name()).to.be.equal("");
            expect(await ERC20Initializable.symbol()).to.be.equal("");
        });

        it("should initialize properly", async function () {
            await ERC20Initializable.__ERC20_init(TOKEN_NAME, TOKEN_SYMBOL);
            expect(await ERC20Initializable.name()).to.be.equal(TOKEN_NAME);
            expect(await ERC20Initializable.symbol()).to.be.equal(TOKEN_SYMBOL);
        });

        it("should be callable only once", async function () {
            await ERC20Initializable.__ERC20_init(TOKEN_NAME, TOKEN_SYMBOL);
            const action = ERC20Initializable.__ERC20_init(TOKEN_NAME, TOKEN_SYMBOL);
            await expect(action).to.be.revertedWith("ERC20 already initialized");
        });
    });
});