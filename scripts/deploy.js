const hre = require("hardhat");

async function main() {
  const TingMeSwap = await hre.ethers.getContractFactory("TingMeSwap");
  const tingMeSwap = await TingMeSwap.deploy(
    "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
    "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
    0,
    "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
  );

  await tingMeSwap.deployed();

  console.log(`deployed to ${tingMeSwap.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
