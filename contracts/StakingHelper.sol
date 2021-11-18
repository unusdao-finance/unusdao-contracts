// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./interfaces/IERC20.sol";

interface IStaking {
    function stake( uint _amount, address _recipient ) external returns ( bool );
    function claim( address _recipient ) external;
}

contract StakingHelper {

    address public immutable staking;
    address public immutable UDO;

    constructor ( address _staking, address _UDO ) public {
        require( _staking != address(0) );
        staking = _staking;
        require( _UDO != address(0) );
        UDO = _UDO;
    }

    function stake( uint _amount ) external {
        IERC20( UDO ).transferFrom( msg.sender, address(this), _amount );
        IERC20( UDO ).approve( staking, _amount );
        IStaking( staking ).stake( _amount, msg.sender );
        IStaking( staking ).claim( msg.sender );
    }
}