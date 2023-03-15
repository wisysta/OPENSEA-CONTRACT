import { ethers } from "hardhat";

async function main() {
    const Exchange = await ethers.getContractFactory("NFTExchange");
    const contract = await Exchange.deploy();
    contract.deployed();

    console.log("AssetShared : ", contract.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
