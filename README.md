# UniswapV2 Sandwich-less DEX

Made for ETH Kyiv Hackathon 2024

Task:

> The idea is to develop an analog of a Uniswap pair where reserve1 \* reserve2 = k, but instead of sequential swaps,
> they are batched into a pool per block. Users can then claim a proportional share of the swap result from the entire
> pool in the next block. Handling the situation when the pool contains both token0 and token1 is open to
> interpretation - justify how your output distribution method is fair.

### Test

Run the tests:

```sh
$ forge test -vvvv
```
