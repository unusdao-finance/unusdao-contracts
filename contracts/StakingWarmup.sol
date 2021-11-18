// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./interfaces/IERC20.sol";

contract StakingWarmup {

    address public immutable staking;
    address public immutable sUDO;

    constructor ( address _staking, address _sUDO ) public {
        require( _staking != address(0) );
        staking = _staking;
        require( _sUDO != address(0) );
        sUDO = _sUDO;
    }

    function retrieve( address _staker, uint _amount ) external {
        require( msg.sender == staking );
        IERC20( sUDO ).transfer( _staker, _amount );
    }
}