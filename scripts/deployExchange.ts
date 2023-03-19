import { ethers } from "hardhat";

async function main() {
    const ProxyRegistry = await ethers.getContractFactory("ProxyRegistry");
    const proxyRegistry = await ProxyRegistry.deploy({ nonce: 19 });

    await proxyRegistry.deployed();

    console.log("Proxy Registry Address :", proxyRegistry.address);

    const Exchange = await ethers.getContractFactory("NFTExchange");
    const exchange = await Exchange.deploy(
        "0x90142c0d7F10a035b47A7a930fEefAcBCaEE3985",
        proxyRegistry.address,
        { nonce: 20 }
    );

    await exchange.deployed();

    console.log("NFT Exchange :", exchange.address);

    await proxyRegistry.functions.grantAuthentication(exchange.address, {
        nonce: 21,
    });
    console.log("Allow exchange to use proxy contracts successfully!");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
