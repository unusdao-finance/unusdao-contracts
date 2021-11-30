// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./interfaces/IPancakeRouter02.sol";
import "./interfaces/IPancakePair.sol";
import "./library/SafeERC20.sol";
import "./library/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

interface ITreasury {
    function valueOf( address _token, uint _amount ) external view returns (uint value_);
}

interface IBond {
    function payoutFor( uint _value ) external view returns ( uint );
    function deposit( 
        uint _amount, 
        uint _maxPrice,
        address _depositor
    ) external returns ( uint );
    
    function bondPrice() external view returns ( uint price_ );
    function principle() external view returns(address token_);
    function UDO() external view returns (address token_);
    function isLiquidityBond() external view returns (bool);
}

contract LPBondHelper is OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public router;
    address public treasury;

    mapping (address=>bool) public authTokens;
    mapping (address=>bool) public authBonds;


   function initialize(
        address _token,
        address _bond,
        address _router,
        address _treasury
    ) external initializer {
        require(_token != address(0));
        require(_bond != address(0));
        require(_router != address(0));
        require(IBond(_bond).isLiquidityBond());

        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        authTokens[_token] = true;
        authBonds[_bond] = true;
        router = _router;
        treasury = _treasury;
    }

    function setAuthToken(address _token, bool _enable) external onlyOwner {
        require(_token != address(0));
        authTokens[_token] = _enable;
    }

    function setAuthBond(address _bond, bool _enable) external onlyOwner {
        require(_bond != address(0));
        require(IBond(_bond).isLiquidityBond());
        authBonds[_bond] = _enable;
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function getPayout(address _bond, address _token, uint256 _amount) external view returns(uint256) {
        require(authBonds[_bond], "no auth bond");
        require(authTokens[_token], "no auth token");

        address principle = IBond(_bond).principle();
        uint256 inAmt = _amount.div(2);
        uint256 outAmt = _getAmountOut(principle, _token, inAmt);
        uint256 lpAmt = _getLPAmount(principle, _token, inAmt, outAmt);
        if (lpAmt == 0) {
            return 0;
        }
        uint value = ITreasury( treasury ).valueOf(principle, lpAmt);
        return IBond(_bond).payoutFor(value).mul(1e9); // payout to bonder is computed
    }

    function _getAmountOut(address _pair, address _tokenIn, uint256 _amountIn) private view returns(uint256) {
        address token0 = IPancakePair(_pair).token0();
        (uint256 r0, uint256 r1, ) = IPancakePair(_pair).getReserves();
        if (r0 == 0 || r1 == 0) {
            return 0;
        }
        (uint256 rIn, uint256 rOut) = (_tokenIn == token0) ? (r0, r1) : (r1, r0);
        return IPancakeRouter02(router).getAmountOut(_amountIn, rIn, rOut);
    }

    function _getLPAmount(address _pair, address _tokenIn, uint256 _inAmt, uint256 _outAmt) private view returns(uint256) {
        (uint256 r0, uint256 r1, ) = IPancakePair(_pair).getReserves();
        if (r0 == 0 || r1 == 0) {
            return 0;
        }
        address token0 = IPancakePair(_pair).token0();
        (uint256 a0, uint256 a1) = (_tokenIn == token0) ? (_inAmt, _outAmt) : (_outAmt, _inAmt);
        uint256 totalSupply = IERC20(_pair).totalSupply();
        uint256 lpAmt = SafeMath.min(a0.mul(totalSupply) / r0, a1.mul(totalSupply) / r1);
        return lpAmt;
    }

    function quickBond(address _bond, address _token, uint256 _amount, address _depositor, uint256 _maxBondPrice, uint256 _minPayout) external whenNotPaused nonReentrant returns (uint256) {
        require(authBonds[_bond], "no auth bond");
        require(authTokens[_token], "no auth token");
        require(_amount > 0, "amount == 0");

        address principle = IBond(_bond).principle();
        address token0 = IPancakePair(principle).token0();
        address token1 = IPancakePair(principle).token1();
        require(_token == token0 || _token == token1);

        uint256 beforeToken0Amt = IERC20(token0).balanceOf(address(this));
        uint256 beforeToken1Amt = IERC20(token1).balanceOf(address(this));

        address outToken = (_token == token0) ? token1 : token0;

        _safeApprove(token0, router);
        _safeApprove(token1, router);

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 lpAmount = _addLiquidity(principle, _token, outToken, _amount);
        uint256 payout = _depositBond(_bond, lpAmount, _depositor, _maxBondPrice);
        require(payout >= _minPayout);

        uint256 afterToken0Amt = IERC20(token0).balanceOf(address(this));
        uint256 afterToken1Amt = IERC20(token1).balanceOf(address(this));

        if (afterToken0Amt > beforeToken0Amt) {
            _safeTransfer(token0, msg.sender, afterToken0Amt -  beforeToken0Amt);
        }

        if (afterToken1Amt > beforeToken1Amt) {
            _safeTransfer(token1, msg.sender, afterToken1Amt -  beforeToken1Amt);
        }

        return payout;
    }

    function _addLiquidity(address _lpToken, address _inToken, address _outToken, uint256 _amount) internal returns (uint256) {
        uint256 inAmt = _amount.div(2);
        uint256 outAmount = _swap(_inToken, _outToken, inAmt);
        return _addLiquidity2(_lpToken, _inToken, _outToken, _amount.sub(inAmt), outAmount);
    }

    function _addLiquidity2(address _principle, address _token0, address _token1, uint256 _token0Amount, uint256 _token1Amount) internal returns (uint256) {
        uint256 beforeLPAmount = IERC20(_principle).balanceOf(address(this));
        IPancakeRouter02(router).addLiquidity(
            _token0,
            _token1,
            _token0Amount,
            _token1Amount,
            0,
            0,
            address(this),
            now + 60
        );

        uint256 afterLPAmount = IERC20(_principle).balanceOf(address(this));
        uint256 lpAmount = afterLPAmount.sub(beforeLPAmount);

        return lpAmount;
    }

    function _swap(address inToken, address outToken, uint256 inAmount) internal returns(uint256 outAmount_){
        uint256 beforeOutAmount = IERC20(outToken).balanceOf(address(this));

        address[] memory  path = new address[](2);
        path[0] = inToken;
        path[1] = outToken;
        IPancakeRouter02(router)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
            inAmount,
            0,
            path,
            address(this),
            now + 60
        );

        uint256 afterOutAmount = IERC20(outToken).balanceOf(address(this));
        outAmount_ = afterOutAmount.sub(beforeOutAmount);
    }
 
    function _depositBond(address _bond, uint256 _amount, address _depositor, uint256 _maxBondPrice) internal returns(uint256){
        address principle = IBond(_bond).principle();
        _safeApprove(principle, _bond);

        return IBond(_bond).deposit(_amount, _maxBondPrice, _depositor);
    }

    function _safeTransfer(address _token, address _to, uint256 _amount) internal {
        if (_amount == 0) return;
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function _safeApprove(address token, address spender) private {
        if (token != address(0) && IERC20(token).allowance(address(this), spender) == 0) {
            IERC20(token).safeApprove(spender, uint256(~0));
        }
    }
}