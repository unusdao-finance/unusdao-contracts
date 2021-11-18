// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../interfaces/IERC20.sol";
import "../interfaces/IPancakePair.sol";
import "../interfaces/IPancakeFactory.sol";
import "../interfaces/IPancakeRouter02.sol";
import "../interfaces/AggregatorV3Interface.sol";
import "../interfaces/IPriceCalculator.sol";
import "../library/HomoraMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract PriceCalculator is IPriceCalculator, OwnableUpgradeable {
    using SafeMath for uint256;
    using HomoraMath for uint256;


    mapping(address => address) public pairTokens;
    mapping(address => address) public tokenFeeds;

    IPancakeFactory public factory;
    address public UDO;
    address public WBNB;
    address public UDO_BUSD;
    address public BUSD;

    bytes32 public constant CAKE_LP = keccak256("Cake-LP");
    bytes32 public constant BSW_LP = keccak256("BSW-LP");

    /* ========== INITIALIZER ========== */

    function initialize(
        address _UDO,
        address _WBNB,
        address _BUSD,
        address _factory
    ) external initializer {
        require(_UDO != address(0));
        require(_WBNB != address(0));
        require(_factory != address(0));

        __Ownable_init();

        UDO = _UDO;
        WBNB = _WBNB;
        BUSD = _BUSD;
        factory = IPancakeFactory(_factory);
    }

    /* ========== Restricted Operation ========== */
    function setUDOBUSD(address _lp) external onlyOwner {
        require(_lp != address(0), "PriceCalculator: invalid address");
        UDO_BUSD = _lp;
    }

    function setPairToken(address _asset, address _pairToken) external onlyOwner {
        require(_asset != address(0) && _pairToken != address(0), "PriceCalculator: invalid address");
        pairTokens[_asset] = _pairToken;
    }

    function setTokenFeed(address _asset, address _feed) external onlyOwner {
        require(_asset != address(0) && _feed != address(0), "PriceCalculator: invalid address");
        tokenFeeds[_asset] = _feed;
    }

    function priceOfBNB() public view  override returns (uint256) {
        (, int price, , ,) = AggregatorV3Interface(tokenFeeds[WBNB]).latestRoundData();
        return uint256(price).mul(1e10);
    }

    function priceOfToken(address token) public view override returns(uint256) {
        if (token == UDO) {
            address token0 = IPancakePair(UDO_BUSD).token0();
            (uint256 r0, uint256 r1, ) = IPancakePair(UDO_BUSD).getReserves();
            (uint256 rUDO, uint256 rBUSD) = (token0 == UDO) ? (r0, r1) : (r1, r0);
            if (rUDO == 0 || rBUSD == 0) {
                return 0;
            }
            uint256 valueInUSD = _oracleValueOf(BUSD, rBUSD);
            return valueInUSD.mul(1e9).div(rUDO);
        } else {
            return valueOfAsset(token, 1e18);
        }
    }

    function valueOfAsset(address asset, uint256 amount) public view returns (uint256) {
        if (asset == address(0) || asset == WBNB) {
            return _oracleValueOf(WBNB, amount);
        } else {
            bytes32 symbol = keccak256(abi.encodePacked(IPancakePair(asset).symbol()));
            if (symbol == CAKE_LP || symbol == BSW_LP) {
                return _getPairPrice(asset, amount);
            } else {
                return _oracleValueOf(asset, amount);
            }
        }
    }

    function _oracleValueOf(address asset, uint256 amount) private view returns (uint256) {
        if (tokenFeeds[asset] != address(0)) {
            (, int price, , ,) = AggregatorV3Interface(tokenFeeds[asset]).latestRoundData();
            return uint256(price).mul(1e10).mul(amount).div(1e18);
        } else {
            address pairToken = pairTokens[asset] == address(0) ? WBNB : pairTokens[asset];
            address pair = factory.getPair(asset, pairToken);
            if (IERC20(asset).balanceOf(pair) == 0) return (0);

            (uint256 r0, uint256 r1, ) = IPancakePair(pair).getReserves();
            (uint256 rAsset, uint256 rPairToken) = (IPancakePair(pair).token0() == asset) ? (r0, r1) : (r1, r0);

            uint256 pairAmount = amount.mul(rPairToken).div(rAsset);           

            if (tokenFeeds[pairToken] != address(0)) {
                (, int price, , ,) = AggregatorV3Interface(tokenFeeds[pairToken]).latestRoundData();
                uint256 valueInUSD = uint256(price).mul(1e10).mul(pairAmount).div(1e18);
                return valueInUSD.mul(2);
            }

            return 0;
        }
    }

    function _getPairPrice(address pair, uint256 amount) private view returns (uint256 valueInUSD) {
        uint256 totalSupply = IPancakePair(pair).totalSupply();
        if (totalSupply == 0) {
            return 0;
        }

        address token0 = IPancakePair(pair).token0();
        address token1 = IPancakePair(pair).token1();
        (uint256 r0, uint256 r1, ) = IPancakePair(pair).getReserves();

        if (tokenFeeds[token0] != address(0)) {
            (, int price, , ,) = AggregatorV3Interface(tokenFeeds[token0]).latestRoundData();
            uint256 rAmount = r0.mul(amount).div(totalSupply);
            valueInUSD = uint256(price).mul(1e10).mul(rAmount).div(1e18);
            return valueInUSD.mul(2);
        } else if (tokenFeeds[token1] != address(0)) {
            (, int price, , ,) = AggregatorV3Interface(tokenFeeds[token1]).latestRoundData();
            uint256 rAmount = r1.mul(amount).div(totalSupply);
            valueInUSD = uint256(price).mul(1e10).mul(rAmount).div(1e18);
            return valueInUSD.mul(2);
        } else {
            return 0;
        }
    }
}