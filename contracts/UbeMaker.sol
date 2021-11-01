// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IUniswapV2ERC20.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Factory.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// T1 - T4: OK
contract UbeMaker is Ownable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  // V1 - V5: OK
  IUniswapV2Factory public immutable factory;
  //0x62d5b84bE28a183aBB507E125B384122D2C25fAE
  // V1 - V5: OK
  address public immutable bar;
  //0x97A9681612482A22b7877afbF8430EDC76159Cae
  // V1 - V5: OK
  address private immutable ube;
  //0x00Be915B9dCf56a3CBE739D9B9c202ca692409EC
  // V1 - V5: OK
  address private immutable celo;
  //0x471EcE3750Da237f93B8E339c536989b8978a438

  // V1 - V5: OK
  mapping(address => address) internal _bridges;

  // E1: OK
  event LogBridgeSet(address indexed token, address indexed bridge);
  // E1: OK
  event LogConvert(
    address indexed server,
    address indexed token0,
    address indexed token1,
    uint256 amount0,
    uint256 amount1,
    uint256 amountUBE
  );

  constructor(
    address _factory,
    address _bar,
    address _ube,
    address _celo
  ) {
    factory = IUniswapV2Factory(_factory);
    bar = _bar;
    ube = _ube;
    celo = _celo;
  }

  // F1 - F10: OK
  // C1 - C24: OK
  function bridgeFor(address token) public view returns (address bridge) {
    bridge = _bridges[token];
    if (bridge == address(0)) {
      bridge = celo;
    }
  }

  // F1 - F10: OK
  // C1 - C24: OK
  function setBridge(address token, address bridge) external onlyOwner {
    // Checks
    require(
      token != ube && token != celo && token != bridge,
      "UbeMaker: Invalid bridge"
    );

    // Effects
    _bridges[token] = bridge;
    emit LogBridgeSet(token, bridge);
  }

  // F1 - F10: OK
  // F6: There is an exploit to add lots of UBE to the bar, run convert, then remove the UBE again.
  //     As the size of the UbeBar has grown, this requires large amounts of funds and isn't super profitable anymore
  // C1 - C24: OK
  function convert(address token0, address token1) external {
    _convert(token0, token1);
  }

  // F1 - F10: OK, see convert
  // C1 - C24: OK
  // C3: Loop is under control of the caller
  function convertMultiple(address[] calldata token0, address[] calldata token1)
    external
  {
    // TODO: This can be optimized a fair bit, but this is safer and simpler for now
    uint256 len = token0.length;
    for (uint256 i = 0; i < len; i++) {
      _convert(token0[i], token1[i]);
    }
  }

  // F1 - F10: OK
  // C1- C24: OK
  function _convert(address token0, address token1) internal {
    // Interactions
    // S1 - S4: OK
    IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(token0, token1));
    require(address(pair) != address(0), "UbeMaker: Invalid pair");
    // balanceOf: S1 - S4: OK
    // transfer: X1 - X5: OK
    IERC20(address(pair)).safeTransfer(
      address(pair),
      pair.balanceOf(address(this))
    );
    // X1 - X5: OK
    (uint256 amount0, uint256 amount1) = pair.burn(address(this));
    if (token0 != pair.token0()) {
      (amount0, amount1) = (amount1, amount0);
    }
    emit LogConvert(
      msg.sender,
      token0,
      token1,
      amount0,
      amount1,
      _convertStep(token0, token1, amount0, amount1)
    );
  }

  // F1 - F10: OK
  // C1 - C24: OK
  // All safeTransfer, _swap, _toUBE, _convertStep: X1 - X5: OK
  function _convertStep(
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1
  ) internal returns (uint256 ubeOut) {
    // Interactions
    if (token0 == token1) {
      uint256 amount = amount0.add(amount1);
      if (token0 == ube) {
        IERC20(ube).safeTransfer(bar, amount);
        ubeOut = amount;
      } else if (token0 == celo) {
        ubeOut = _toUBE(celo, amount);
      } else {
        address bridge = bridgeFor(token0);
        amount = _swap(token0, bridge, amount, address(this));
        ubeOut = _convertStep(bridge, bridge, amount, 0);
      }
    } else if (token0 == ube) {
      // eg. UBE - ETH
      IERC20(ube).safeTransfer(bar, amount0);
      ubeOut = _toUBE(token1, amount1).add(amount0);
    } else if (token1 == ube) {
      // eg. USDT - UBE
      IERC20(ube).safeTransfer(bar, amount1);
      ubeOut = _toUBE(token0, amount0).add(amount1);
    } else if (token0 == celo) {
      // eg. CELO - mcUSD
      ubeOut = _toUBE(
        celo,
        _swap(token1, celo, amount1, address(this)).add(amount0)
      );
    } else if (token1 == celo) {
      // eg. mcUSD - CELO
      ubeOut = _toUBE(
        celo,
        _swap(token0, celo, amount0, address(this)).add(amount1)
      );
    } else {
      // eg. MIC - USDT
      address bridge0 = bridgeFor(token0);
      address bridge1 = bridgeFor(token1);
      if (bridge0 == token1) {
        // eg. MIC - USDT - and bridgeFor(MIC) = USDT
        ubeOut = _convertStep(
          bridge0,
          token1,
          _swap(token0, bridge0, amount0, address(this)),
          amount1
        );
      } else if (bridge1 == token0) {
        // eg. WBTC - DSD - and bridgeFor(DSD) = WBTC
        ubeOut = _convertStep(
          token0,
          bridge1,
          amount0,
          _swap(token1, bridge1, amount1, address(this))
        );
      } else {
        ubeOut = _convertStep(
          bridge0,
          bridge1, // eg. USDT - DSD - and bridgeFor(DSD) = WBTC
          _swap(token0, bridge0, amount0, address(this)),
          _swap(token1, bridge1, amount1, address(this))
        );
      }
    }
  }

  // F1 - F10: OK
  // C1 - C24: OK
  // All safeTransfer, swap: X1 - X5: OK
  function _swap(
    address fromToken,
    address toToken,
    uint256 amountIn,
    address to
  ) internal returns (uint256 amountOut) {
    // Checks
    // X1 - X5: OK
    IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(fromToken, toToken));
    require(address(pair) != address(0), "UbeMaker: Cannot convert");

    // Interactions
    // X1 - X5: OK
    (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
    uint256 amountInWithFee = amountIn.mul(997);
    if (fromToken == pair.token0()) {
      amountOut =
        amountInWithFee.mul(reserve1) /
        reserve0.mul(1000).add(amountInWithFee);
      IERC20(fromToken).safeTransfer(address(pair), amountIn);
      pair.swap(0, amountOut, to, new bytes(0));
      // TODO: Add maximum slippage?
    } else {
      amountOut =
        amountInWithFee.mul(reserve0) /
        reserve1.mul(1000).add(amountInWithFee);
      IERC20(fromToken).safeTransfer(address(pair), amountIn);
      pair.swap(amountOut, 0, to, new bytes(0));
      // TODO: Add maximum slippage?
    }
  }

  // F1 - F10: OK
  // C1 - C24: OK
  function _toUBE(address token, uint256 amountIn)
    internal
    returns (uint256 amountOut)
  {
    // X1 - X5: OK
    amountOut = _swap(token, ube, amountIn, bar);
  }
}
