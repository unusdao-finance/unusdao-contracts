// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./helpers/ERC20.sol";
import "./library/SafeERC20.sol";

interface IStaking {
    function stake( uint _amount, address _recipient ) external returns ( bool );

    function unstake( uint _amount, address _recipient ) external returns ( bool );

    function index() external view returns ( uint );
}

contract wUDO is ERC20 {
    using SafeERC20 for ERC20;
    using Address for address;
    using SafeMath for uint;

    address public immutable staking;
    address public immutable UDO;
    address public immutable sUDO;

    constructor( address _staking, address _UDO, address _sUDO ) ERC20( 'Wrapped sUDO', 'wsUDO' ) public {
        require( _staking != address(0) );
        staking = _staking;
        require( _UDO != address(0) );
        UDO = _UDO;
        require( _sUDO != address(0) );
        sUDO = _sUDO;
    }

    /**
        @notice stakes UDO and wraps sUDO
        @param _amount uint
        @return uint
     */
    function wrapFromUDO( uint _amount ) external returns ( uint ) {
        IERC20( UDO ).transferFrom( msg.sender, address(this), _amount );

        IERC20( UDO ).approve( staking, _amount ); // stake UDO for sUDO
        IStaking( staking ).stake( _amount, address(this) );

        uint value = wUDOValue( _amount );
        _mint( msg.sender, value );
        return value;
    }

    /**
        @notice unwrap sUDO and unstake UDO
        @param _amount uint
        @return uint
     */
    function unwrapToUDO( uint _amount ) external returns ( uint ) {
        _burn( msg.sender, _amount );
        
        uint value = sUDOValue( _amount );
        IERC20( sUDO ).approve( staking, value ); // unstake sUDO for UDO
        IStaking( staking ).unstake( value, address(this) );

        IERC20( UDO ).transfer( msg.sender, value );
        return value;
    }

    /**
        @notice wrap sUDO
        @param _amount uint
        @return uint
     */
    function wrapFromsUDO( uint _amount ) external returns ( uint ) {
        IERC20( sUDO ).transferFrom( msg.sender, address(this), _amount );
        
        uint value = wUDOValue( _amount );
        _mint( msg.sender, value );
        return value;
    }

    /**
        @notice unwrap sUDO
        @param _amount uint
        @return uint
     */
    function unwrapTosUDO( uint _amount ) external returns ( uint ) {
        _burn( msg.sender, _amount );

        uint value = sUDOValue( _amount );
        IERC20( sUDO ).transfer( msg.sender, value );
        return value;
    }

    /**
        @notice converts wUDO amount to sUDO
        @param _amount uint
        @return uint
     */
    function sUDOValue( uint _amount ) public view returns ( uint ) {
        return _amount.mul( IStaking( staking ).index() ).div( 10 ** decimals() );
    }

    /**
        @notice converts sUDO amount to wUDO
        @param _amount uint
        @return uint
     */
    function wUDOValue( uint _amount ) public view returns ( uint ) {
        return _amount.mul( 10 ** decimals() ).div( IStaking( staking ).index() );
    }

}