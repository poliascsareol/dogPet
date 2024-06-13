// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract DogPet is ERC20, Ownable {
    IUniswapV2Router02 private router;
    address private pair;

    mapping(address => bool) private _isAddLiquidityAddress;

    address public destroyAddress = 0xe7dB3e0A94306f6668219264FcaA900763251174;
    address public dividendAddress = 0xa7365Fb3eE006d20457EeBfd34746928F0BD081b;
    address public foundationAddress = 0xB6EC9AE10a94d40a1270E2F9F136cA0804CE8462;
    address public marketAddress = 0x0C16Cae23a54934f3E5373Ff837958Ae9a3a7516;
    address public gameMitAddress = 0x4B92F75d4487978b7fEB78C4b72E4d1Ca6ED97EB;
    address public forPinkSaleAddress = 0x7fCD0c72B846bE906552DceCD51C60a0396E093e;

    uint256 private lastFoundationAmount;
    uint256 private lastMarketAmount;
    uint256 private destroyTotal;

    uint256 public sellTime;
    uint256 public lastRecordedTime;

    address public routerAddress = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address public zeroAddress = 0x0000000000000000000000000000000000000000;
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;
    address public usdtAddress = 0x55d398326f99059fF775485246999027B3197955;

    uint256 public constant SELL_FEE = 6; // 6%
    uint256 public constant BUY_FEE = 6; // 6%
    uint256 public constant FOUNDATION_FEE = 2; // 2%
    uint256 public constant MARKET_FEE = 2; // 2%
    uint256 public constant SLIPPAGE = 80; // 80%

    bool public sellResume = true;

    event AddLiquidityAddressSet(address indexed liquidityAddress, bool status);
    event SwapAndSendTo(address indexed recipient, uint256 amount);
    event TokensDestroyed(uint256 amount);

    constructor() ERC20("DOGPET", "DP") {
        uint256 totalSupply = 21000000000 ether;

        // Mint 80% of the total supply to the foundationAddress.
        // These tokens will be used for community private placements and will not be largely held before the market launch.
        // Any tokens not sold in the private placement will be sent to the burn address.
        _mint(foundationAddress, totalSupply * 80 / 100);
        _mint(gameMitAddress, totalSupply * 10 / 100);
        _mint(forPinkSaleAddress, totalSupply * 10 / 100);

        router = IUniswapV2Router02(routerAddress);
        pair = IUniswapV2Factory(router.factory()).createPair(address(this), usdtAddress);
        _isAddLiquidityAddress[foundationAddress] = true;
        _isAddLiquidityAddress[destroyAddress] = true;
        _isAddLiquidityAddress[dividendAddress] = true;
        _isAddLiquidityAddress[marketAddress] = true;
        _isAddLiquidityAddress[gameMitAddress] = true;
        _isAddLiquidityAddress[forPinkSaleAddress] = true;
        lastRecordedTime = block.timestamp + 1 hours;
        sellTime = block.timestamp;
    }

    function setAddLiquidityAddress(address liquidityAddress, bool status) external onlyOwner {
        require(liquidityAddress != address(0), "Liquidity address cannot be zero");
        _isAddLiquidityAddress[liquidityAddress] = status;
        emit AddLiquidityAddressSet(liquidityAddress, status);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "ERC20: transfer amount must be greater than zero");

        if (
            address(this) != from && address(this) != to &&
            !_isAddLiquidityAddress[from] && !_isAddLiquidityAddress[to] &&
            (pair == from || pair == to) && from != destroyAddress
        ) {

            uint256 lpBalance = balanceOf(pair);
            uint256 maxAmount = lpBalance / 2;

            if (amount > maxAmount) {
                revert("Transfer amount exceeds 50% of the pair's liquidity pool balance");
            }

            if (pair == to) {
                // Sell
                // After destroying 0.5% of the LP pool, stop trading for ten minutes
                // and allow foundationAddress to balance the price. After balancing, trading can resume.
                // This cooldown trading balance mechanism is explained in the whitepaper and has been approved by community vote.
                require(block.timestamp >= sellTime || _isAddLiquidityAddress[from] || sellResume, "Sell After balancing, trading can resume.");
                if (sellResume == false && _isAddLiquidityAddress[from]) {
                    sellResume = true;
                }
                _handleSell(from, to, amount);
            } else {
                // Buy
                _handleBuy(from, to, amount);
            }
        } else {
            if (destroyAddress == from) {
                super._transfer(from, to, amount);
                _destroyTokens();
            } else {
                super._transfer(from, to, amount);
            }
        }
    }

    function _handleSell(address from, address to, uint256 amount) private {
        _swapAndTransferFees(from, amount, true);
        uint256 sellAmount = amount * (100 - SELL_FEE) / 100;
        super._transfer(from, to, sellAmount);

        if (block.timestamp >= lastRecordedTime) {
            uint256 lpAmount = balanceOf(pair);
            if (lpAmount >= 21000000 ether) {
                destroyTotal = lpAmount * 5 / 1000;
                lastRecordedTime = block.timestamp + 1 hours;
                _destroyTokens();
            }
        }
    }

    function _handleBuy(address from, address to, uint256 amount) private {
        _swapAndTransferFees(from, amount, false);
        uint256 buyAmount = amount * (100 - BUY_FEE) / 100;
        super._transfer(from, to, buyAmount);
    }

    function _swapAndTransferFees(address from, uint256 amount, bool isSell) private {
        uint256 fee = amount * FOUNDATION_FEE / 100;
        lastFoundationAmount += fee;
        lastMarketAmount += fee;

        super._transfer(from, address(this), fee * 2);
        super._transfer(from, dividendAddress, fee);

        if (isSell) {
            _sellSwapToWeight(lastFoundationAmount, foundationAddress);
            _sellSwapToWeight(lastMarketAmount, marketAddress);
            lastFoundationAmount = 0;
            lastMarketAmount = 0;
        }
    }

    function _destroyTokens() private {
        sellResume == false;
        if (destroyTotal > 0) {
            sellTime = block.timestamp + 10 minutes;
            super._transfer(pair, burnAddress, destroyTotal);
            IUniswapV2Pair(pair).sync();
            destroyTotal = 0;
            emit TokensDestroyed(destroyTotal);
        }
    }

    function _sellSwapToWeight(uint256 amount, address to) private {
        if (amount > 0) {
            address[] memory path = new address[](2);
            path[0] = address(this);
            path[1] = usdtAddress;

            uint256[] memory amountsOut = router.getAmountsOut(amount, path);
            uint256 minOutputAmount = amountsOut[1] * SLIPPAGE / 100; // 80% of the expected output amount
            _approve(address(this), address(router), amount);
            router.swapExactTokensForTokensSupportingFeeOnTransferTokens(amount, minOutputAmount, path, to, block.timestamp);
            emit SwapAndSendTo(to, amount);
        }
    }
}
