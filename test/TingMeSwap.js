const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
// const { ethers } = require("hardhat-ethers");
describe("TingMeSwap", function () {
  let impersonatedZeroSigner, Swap, provider, swap;
  const erc20Abi =
    require("../artifacts/contracts/interfaces/IERC20.sol/IERC20.json")["abi"];
  this.beforeEach(async () => {
    impersonatedZeroSigner = await ethers.getImpersonatedSigner(
      "0x0000000000000000000000000000000000000000"
    );
    Swap = await ethers.getContractFactory("TingMeSwap");
    provider = ethers.provider;
    swap = await Swap.connect(impersonatedZeroSigner).deploy(
      "0x1111111254eeb25477b68fb85ed929f73a960582",
      "0x8731d54E9D02c286767d56ac03e8037C07e01e98",
      0,
      "0x0000000000000000000000000000000000000000"
    );
    await swap.deployed();
  });
  // it("Should impersonate successfully", async () => {
  //   const impersonatedZeroSigner = await ethers.getImpersonatedSigner(
  //     "0x0000000000000000000000000000000000000000"
  //   );
  //   const balance = await provider.getBalance(impersonatedZeroSigner.address);
  //   console.log(balance);
  // });
  // it("Should deploy successfully", async () => {
  //   console.log(swap.address);
  // });
  it("Should swap single chain sucessfully", async () => {
    const oneInchContract = await ethers.getContractAt(
      erc20Abi,
      "0x111111111117dc0aa78b770fa6a738034120c302"
    );
    const beforeBalanceOf = await oneInchContract.balanceOf(
      impersonatedZeroSigner.address
    );
    console.log(beforeBalanceOf);
    const tx = await swap
      .connect(impersonatedZeroSigner)
      .swapSingleChain(
        "0x12aa3caf0000000000000000000000007122db0ebe4eb9b434a9f2ffe6760bc03bfbd0e0000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000111111111117dc0aa78b770fa6a738034120c3020000000000000000000000007122db0ebe4eb9b434a9f2ffe6760bc03bfbd0e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002386f26fc100000000000000000000000000000000000000000000000000016da5921f73134826000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cd0000000000000000000000000000000000000000000000af00002000000600206b4be0b94041c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2d0e30db00c20c02aaa39b223fe8d0a0e5c4f27ead9083c756cc226aad2da94c59524ac0d93f6d6cbf9071d7086f26ae4071138002dc6c026aad2da94c59524ac0d93f6d6cbf9071d7086f21111111254eeb25477b68fb85ed929f73a9605820000000000000000000000000000000000000000000000000000000000000001c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000cfee7c08",
        { value: "10000000000000000" }
      );
    txdone = await tx.wait();
    // console.log(txdone);
  });
});
