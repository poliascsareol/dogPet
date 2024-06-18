// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./utils/Constants.sol";

contract DogPet is ERC20, Ownable, ReentrancyGuard {
    IUniswapV2Router02 private router;
    address private pair;

    mapping(address => bool) private _isAddLiquidityAddress;

    // Multi-sig wallet address: 0x7EE337730EeBfbFA918e0070ebFD8595e3579d9d
    // Signer 1: 0xB6EC9AE10a94d40a1270E2F9F136cA0804CE8462
    // Signer 2: 0xe509Eb736251C36d413C1ff2aF0f848A67B0b6d8
    // Signer 3: 0x66d6C29D159bAE098a96a85A8A99da93d6ef5BfE
    // Signer 4: 0x0A210631DD7f2EA689b2c38C4D33D21f55C86c9c
    // Signer 5: 0x8E20735d0a7958183673c53e3412D4b4c5011942
    address public destroyAddress = 0x7EE337730EeBfbFA918e0070ebFD8595e3579d9d;
    address public dividendAddress = 0xa7365Fb3eE006d20457EeBfd34746928F0BD081b;

    address public foundationAddress = 0xB6EC9AE10a94d40a1270E2F9F136cA0804CE8462;
    address public marketAddress = 0x0C16Cae23a54934f3E5373Ff837958Ae9a3a7516;
    address public gameMitAddress = 0x4B92F75d4487978b7fEB78C4b72E4d1Ca6ED97EB;
    address public forPinkSaleAddress = 0x7fCD0c72B846bE906552DceCD51C60a0396E093e;

    uint256 private lastFoundationAmount;
    uint256 private lastMarketAmount;

    uint256 public sellTime;
    uint256 public lastRecordedTime;

    uint256 public constant SELL_FEE = 6; // 6%
    uint256 public constant BUY_FEE = 6; // 6%
    uint256 public constant _FEE = 2; // 2%
    uint256 public constant SLIPPAGE = 90; // 90%

    bool public sellResume = true;

    event AddLiquidityAddressSet(address indexed liquidityAddress, bool status);
    event SwapAndSendTo(address indexed recipient, uint256 amount);
    event TokensDestroyed(uint256 amount);

    constructor() ERC20("DOGPET", "DP") {
        uint256 totalSupply = 21000000000 ether;

        _mint(Constants.burnAddress, totalSupply * 75 / 100);
        _mint(foundationAddress, totalSupply * 5 / 100);
        _mint(gameMitAddress, totalSupply * 10 / 100);
        _mint(forPinkSaleAddress, totalSupply * 10 / 100);

        router = IUniswapV2Router02(Constants.routerAddress);
        pair = IUniswapV2Factory(router.factory()).createPair(address(this), Constants.usdtAddress);
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
                require(block.timestamp >= sellTime || _isAddLiquidityAddress[from] || sellResume, "Sell: Trading is temporarily disabled.");
                if (_isAddLiquidityAddress[from]) {
                    sellResume = true;
                }
                _handleSell(from, to, amount);
            } else {
                // Buy
                _handleBuy(from, to, amount);
            }
        } else {
            super._transfer(from, to, amount);
            if (destroyAddress == from) {
                _destroyTokens();
            }
        }
    }

    function _handleSell(address from, address to, uint256 amount) private {
        _swapAndTransferFees(from, amount, true);
        uint256 sellAmount = amount * (100 - SELL_FEE) / 100;
        super._transfer(from, to, sellAmount);
    }

    function _handleBuy(address from, address to, uint256 amount) private {
        _swapAndTransferFees(from, amount, false);
        uint256 buyAmount = amount * (100 - BUY_FEE) / 100;
        super._transfer(from, to, buyAmount);
    }

    function _swapAndTransferFees(address from, uint256 amount, bool isSell) private nonReentrant {
        uint256 fee = amount * _FEE / 100;
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

    function _sellSwapToWeight(uint256 amount, address to) private {
        if (amount > 0) {
            address[] memory path = new address[](2);
            path[0] = address(this);
            path[1] = Constants.usdtAddress;

            uint256[] memory amountsOut = router.getAmountsOut(amount, path);
            uint256 minOutputAmount = amountsOut[1] * SLIPPAGE / 100; // 90% of the expected output amount
            _approve(address(this), address(router), amount);
            router.swapExactTokensForTokensSupportingFeeOnTransferTokens(amount, minOutputAmount, path, to, block.timestamp);
            emit SwapAndSendTo(to, amount);
        }
    }

    function _destroyTokens() private {
        sellResume = false;
        if (block.timestamp >= lastRecordedTime) {
            uint256 lpAmount = balanceOf(pair);
            if (lpAmount >= 21000000 ether) {
                uint256 destroyAmount = lpAmount * 5 / 1000;
                lastRecordedTime = block.timestamp + 1 hours;
                if (destroyAmount > 0) {
                    sellTime = block.timestamp + 10 minutes;
                    super._transfer(pair, Constants.burnAddress, destroyAmount);
                    IUniswapV2Pair(pair).sync();
                    emit TokensDestroyed(destroyAmount);
                }
            }
        }
    }
}
