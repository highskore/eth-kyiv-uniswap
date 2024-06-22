// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Test } from "forge-std/src/Test.sol";
import { console2 } from "forge-std/src/console2.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { UniswapV2Pair } from "../src/UniswapV2Pair.sol";

contract UniswapV2PairTest is Test {
    UniswapV2Pair public pair;
    IERC20 internal dai;
    IERC20 internal usdc;
    address user;
    address chef;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

        user = address(0xc5FCb81DfBD30563A50cb8160C9beee7f2EF44F9);
        chef = address(0xD1668fB5F690C59Ab4B0CAbAd0f8C1617895052B);

        vm.createSelectFork({ urlOrAlias: "mainnet" });

        vm.label(address(dai), "DAI");
        vm.label(address(usdc), "USDC");
        vm.label(user, "USER");
        vm.label(chef, "CHEF");

        pair = new UniswapV2Pair();
        pair.initialize(address(dai), address(usdc));

        vm.label(address(pair), "POOL");

        // Prank to USDC Faucet
        vm.startPrank(0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa);
        usdc.transfer(address(user), 20_000_000_000_000);
        usdc.transfer(address(chef), 20_000_000_000_000);

        // Prank the user
        vm.startPrank(user);

        // Setup liquidity
        dai.transfer(address(pair), 100_000_000_000_000_000_000);
        usdc.transfer(address(pair), 200_000_000);
        pair.mint(user);
    }

    /// @dev Basic test. Run it with `forge test -vvv` to see the console log.
    function test_token0_token0_claim() public {
        // Prank the user
        vm.startPrank(user);

        // Check reserves before
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        uint256 amountIn = 10_000_000_000_000_000_000;

        // Get amount out for 100 DAI
        uint256 amountOut = getAmountOut(amountIn, reserve0, reserve1);

        // Transfer 10 DAI to the pair
        dai.transfer(address(pair), amountIn);

        // Swap 100 DAI for USDC
        pair.swap(0, amountOut, user, bytes(""));

        // Check reserves before
        (reserve0, reserve1,) = pair.getReserves();

        // Get amount out for 100 DAI
        amountOut = getAmountOut(amountIn, reserve0, reserve1);

        // Prank the user
        vm.startPrank(chef);

        // Transfer 10 DAI to the pair
        dai.transfer(address(pair), amountIn);

        // Swap 10 DAI for USDC
        pair.swap(0, amountOut, chef, bytes(""));

        // Roll to next block
        vm.roll(block.number + 1);

        // Claim the rewards
        pair.claim(block.number - 1);

        // Prank to the user
        vm.startPrank(user);

        // Claim the rewards
        pair.claim(block.number - 1);
    }

    function test_token0_token1_claim() public {
        // Prank the user
        vm.startPrank(chef);

        // Check reserves before
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        uint256 amountIn0 = 10_000_000_000_000_000_000;

        // Get amount out for 100 DAI
        uint256 amountOut = getAmountOut(amountIn0, reserve0, reserve1);

        // Transfer 10 DAI to the pair
        dai.transfer(address(pair), amountIn0);

        // Swap 10 DAI for USDC
        pair.swap(0, amountOut, user, bytes(""));

        // Check reserves before
        (reserve0, reserve1,) = pair.getReserves();

        uint256 amountIn1 = 20_000_000;

        // Get amount out for 100 DAI
        amountOut = getAmountOut(amountIn1, reserve1, reserve0);

        // Prank the user
        vm.startPrank(user);

        // Transfer 10 DAI to the pair
        usdc.transfer(address(pair), amountIn1);

        // Swap 20 USDC for DAI
        pair.swap(amountOut, 0, chef, bytes(""));

        // Roll to next block
        vm.roll(block.number + 1);

        // Claim the rewards
        pair.claim(block.number - 1);

        // Prank to the chef
        vm.startPrank(chef);

        // Claim the rewards
        pair.claim(block.number - 1);
    }

    function test_token0_token1_token0_token1_claim() public {
        // Prank the chef
        vm.startPrank(chef);

        // Check reserves before
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        uint256 amountIn0 = 10_000_000_000_000_000_000;

        // Get amount out for 100 DAI
        uint256 amountOut = getAmountOut(amountIn0, reserve0, reserve1);

        // Transfer 10 DAI to the pair
        dai.transfer(address(pair), amountIn0);

        // Swap 10 DAI for USDC
        pair.swap(0, amountOut, chef, bytes(""));

        // Check reserves before
        (reserve0, reserve1,) = pair.getReserves();

        uint256 amountIn1 = 5_000_000;

        // Get amount out for 100 DAI
        amountOut = getAmountOut(amountIn1, reserve1, reserve0);

        // Prank the user
        vm.startPrank(user);

        // Transfer 10 DAI to the pair
        usdc.transfer(address(pair), amountIn1);

        // Swap 20 USDC for DAI
        pair.swap(amountOut, 0, user, bytes(""));

        // Prank the chef
        vm.startPrank(chef);

        // Check reserves before
        (reserve0, reserve1,) = pair.getReserves();

        amountIn0 = 30_000_000_000_000_000_000;

        // Get amount out for 100 DAI
        amountOut = getAmountOut(amountIn0, reserve0, reserve1);

        // Transfer 10 DAI to the pair
        dai.transfer(address(pair), amountIn0);

        // Swap 10 DAI for USDC
        pair.swap(0, amountOut, chef, bytes(""));

        // Check reserves before
        (reserve0, reserve1,) = pair.getReserves();

        amountIn1 = 20_000_000;

        // Get amount out for 100 DAI
        amountOut = getAmountOut(amountIn1, reserve1, reserve0);

        // Prank the user
        vm.startPrank(user);

        // Transfer 10 DAI to the pair
        usdc.transfer(address(pair), amountIn1);

        // Swap 20 USDC for DAI
        pair.swap(amountOut, 0, user, bytes(""));

        // Roll to next block
        vm.roll(block.number + 1);

        // Claim the rewards
        pair.claim(block.number - 1);

        // Prank to the chef
        vm.startPrank(chef);

        // Claim the rewards
        pair.claim(block.number - 1);
    }

    function test_token1_token0_token1_token0_claim() public {
        // Prank the chef
        vm.startPrank(chef);

        // Check reserves before
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        uint256 amountIn0 = 10_000_000;

        // Get amount out for 100 DAI
        uint256 amountOut = getAmountOut(amountIn0, reserve1, reserve0);

        // Transfer 10 USDC to the pair
        usdc.transfer(address(pair), amountIn0);

        // Swap 10 DAI for USDC
        pair.swap(amountOut, 0, chef, bytes(""));

        // Check reserves before
        (reserve0, reserve1,) = pair.getReserves();

        uint256 amountIn1 = 5_000_000_000_000_000_000;

        // Get amount out for 100 DAI
        amountOut = getAmountOut(amountIn1, reserve0, reserve1);

        // Prank the user
        vm.startPrank(user);

        // Transfer 10 DAI to the pair
        dai.transfer(address(pair), amountIn1);

        // Swap 20 USDC for DAI
        pair.swap(0, amountOut, user, bytes(""));

        // Prank the chef
        vm.startPrank(chef);

        // Check reserves before
        (reserve0, reserve1,) = pair.getReserves();

        amountIn0 = 30_000_000;

        // Get amount out for 30 USDC
        amountOut = getAmountOut(amountIn0, reserve1, reserve0);

        // Transfer 30 USDC to the pair
        usdc.transfer(address(pair), amountIn0);

        // Swap 30 USDC for DAI
        pair.swap(amountOut, 0, chef, bytes(""));

        // Check reserves before
        (reserve0, reserve1,) = pair.getReserves();

        amountIn1 = 20_000_000_000_000_000_000;

        // Get amount out for 20 DAI
        amountOut = getAmountOut(amountIn1, reserve0, reserve1);

        // Prank the user
        vm.startPrank(user);

        // Transfer 20 DAI to the pair
        dai.transfer(address(pair), amountIn1);

        // Swap 20 DAI for USDC
        pair.swap(0, amountOut, user, bytes(""));

        // Roll to next block
        vm.roll(block.number + 1);

        // Claim the rewards
        pair.claim(block.number - 1);

        // Prank to the chef
        vm.startPrank(chef);

        // Claim the rewards
        pair.claim(block.number - 1);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    )
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + (amountInWithFee);
        amountOut = numerator / denominator;
    }
}
