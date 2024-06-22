// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.8.25;

import { IUniswapV2Pair } from "./interfaces/IUniswapV2Pair.sol";
import { UniswapV2ERC20 } from "./UniswapV2ERC20.sol";
import { Math } from "./libraries/Math.sol";
import { UQ112x112 } from "./libraries/UQ112x112.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IUniswapV2Factory } from "./interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Callee } from "./interfaces/IUniswapV2Callee.sol";
import { console2 } from "forge-std/src/console2.sol";

contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    using UQ112x112 for uint224;

    struct SwapLog {
        uint256 amount0in;
        uint256 amount1in;
        uint256 amount0out;
        uint256 amount1out;
        address to;
        uint256 reserve0;
        uint256 reserve1;
        bool claimed;
    }

    struct BalancesPerBlack {
        uint256 outstandingbalance0;
        uint256 outstandingbalance1;
        uint256 instandingbalance0;
        uint256 instandingbalance1;
    }

    uint256 public totalOutstandingbalance0;
    uint256 public totalOutstandingbalance1;
    mapping(uint256 => BalancesPerBlack) public balancesPerBlock;
    mapping(uint256 => SwapLog[]) public swapsPerBlock;

    uint256 public constant override MINIMUM_LIQUIDITY = 10 ** 3;

    address public override factory;
    address public override token0;
    address public override token1;

    uint112 private reserve0; // uses single storage slot, accessible via getReserves
    uint112 private reserve1; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint256 public override price0CumulativeLast;
    uint256 public override price1CumulativeLast;
    uint256 public override kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint256 private unlocked = 1;

    modifier lock() {
        require(unlocked == 1, "UniswapV2: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves()
        public
        view
        override
        returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast)
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "UniswapV2: TRANSFER_FAILED");
    }

    constructor() {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external override {
        require(msg.sender == factory, "UniswapV2: FORBIDDEN"); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "UniswapV2: OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        unchecked {
            uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
            if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
                // * never overflows, and + overflow is desired
                price0CumulativeLast += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
                price1CumulativeLast += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
            }
        }
        reserve0 = uint112(balance0 - totalOutstandingbalance0);
        reserve1 = uint112(balance1 - totalOutstandingbalance1);
        console2.log("--------------------");
        console2.log("reserve0", reserve0);
        console2.log("reserve1", reserve1);
        console2.log("balance0", balance0);
        console2.log("balance1", balance1);
        console2.log("totalOutstandingbalance0", totalOutstandingbalance0);
        console2.log("totalOutstandingbalance1", totalOutstandingbalance1);
        console2.log("--------------------");

        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = address(0);
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = Math.sqrt(uint256(_reserve0) * _reserve1);
                uint256 rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply * (rootK - rootKLast);
                    uint256 denominator = rootK * 5 + rootKLast;
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external override lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - totalOutstandingbalance0 - _reserve0;
        uint256 amount1 = balance1 - totalOutstandingbalance1 - _reserve1;

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in
            // _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min((amount0 * _totalSupply) / _reserve0, (amount1 * _totalSupply) / _reserve1);
        }
        require(liquidity > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external override lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in
            // _mintFee
        amount0 = (liquidity * (balance0 - totalOutstandingbalance0)) / _totalSupply; // using balances ensures pro-rata
            // distribution
        amount1 = (liquidity * (balance1 - totalOutstandingbalance1)) / _totalSupply; // using balances ensures pro-rata
            // distribution
        require(amount0 > 0 && amount1 > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external override lock {
        require(amount0Out > 0 || amount1Out > 0, "UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "UniswapV2: INSUFFICIENT_LIQUIDITY");

        uint256 balance0;
        uint256 balance1;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, "UniswapV2: INVALID_TO");
            if (data.length > 0) {
                IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
            }
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }

        // Update totalOutstandingbalance0 and totalOutstandingbalance1
        totalOutstandingbalance0 += amount0Out;
        totalOutstandingbalance1 += amount1Out;

        uint256 amount0In = balance0 - totalOutstandingbalance0 > _reserve0 - amount0Out
            ? balance0 - totalOutstandingbalance0 - (_reserve0 - amount0Out)
            : 0;
        uint256 amount1In = balance1 - totalOutstandingbalance1 > _reserve1 - amount1Out
            ? balance1 - totalOutstandingbalance1 - (_reserve1 - amount1Out)
            : 0;
        require(amount0In > 0 || amount1In > 0, "UniswapV2: INSUFFICIENT_INPUT_AMOUNT");
        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            uint256 balance0Adjusted = (balance0 - totalOutstandingbalance0) * 1000 - amount0In * 3;
            uint256 balance1Adjusted = (balance1 - totalOutstandingbalance1) * 1000 - amount1In * 3;
            require(balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * _reserve1 * 1e6, "UniswapV2: K");
        }

        // push amountOut as outstanding balance and input amount as instanding balance
        balancesPerBlock[block.number].outstandingbalance0 += amount0Out;
        balancesPerBlock[block.number].outstandingbalance1 += amount1Out;
        balancesPerBlock[block.number].instandingbalance0 += amount0In;
        balancesPerBlock[block.number].instandingbalance1 += amount1In;

        // push swap to swapsPerBlock
        swapsPerBlock[block.number].push(
            SwapLog({
                amount0in: amount0In,
                amount1in: amount1In,
                amount0out: amount0Out,
                amount1out: amount1Out,
                to: to,
                reserve0: _reserve0,
                reserve1: _reserve1,
                claimed: false
            })
        );

        // update reserves
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function claim(uint256 _block) external {
        if (_block >= block.number) {
            return;
        }
        // Init totalInputAmount0 and totalInputAmount1
        uint256 totalInputAmount0 = balancesPerBlock[_block].instandingbalance0;
        uint256 totalInputAmount1 = balancesPerBlock[_block].instandingbalance1;
        uint256 totalOutputAmount0 = balancesPerBlock[_block].outstandingbalance0;
        uint256 totalOutputAmount1 = balancesPerBlock[_block].outstandingbalance1;
        // Iterate over all swaps in the block
        for (uint256 i = 0; i < swapsPerBlock[_block].length; i++) {
            // Check if msg.sender is the recipient of the swap and if the swap has not been claimed yet
            if (swapsPerBlock[_block][i].to == msg.sender && !swapsPerBlock[_block][i].claimed) {
                // Calculate the amount of input and output tokens for the swap
                uint256 inputAmount0 = swapsPerBlock[_block][i].amount0in;
                uint256 inputAmount1 = swapsPerBlock[_block][i].amount1in;
                // Calculate the share of the input and output tokens for the recipient
                uint256 share0;
                if (totalInputAmount1 > 0) {
                    share0 = (inputAmount1 * totalOutputAmount0 / totalInputAmount1);
                }
                uint256 share1;
                if (totalInputAmount0 > 0) {
                    share1 = (inputAmount0 * totalOutputAmount1 / totalInputAmount0);
                }
                // Transfer the share of the input and output tokens to the recipient
                if (share0 > 0) {
                    totalOutstandingbalance0 -= share0;
                    _safeTransfer(token0, msg.sender, share0);
                }
                if (share1 > 0) {
                    totalOutstandingbalance1 -= share1;
                    _safeTransfer(token1, msg.sender, share1);
                }
                // Mark the swap as claimed
                swapsPerBlock[_block][i].claimed = true;
            }
        }
    }

    // force balances to match reserves
    function skim(address to) external override lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)) - totalOutstandingbalance0 - reserve0);
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)) - totalOutstandingbalance1 - reserve1);
    }

    // force reserves to match balances
    function sync() external override lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}
