// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./library/SafeERC20.sol";
import "./interfaces/IsUDO.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

interface IWarmup {
    function retrieve( address staker_, uint amount_ ) external;
}

interface IDistributor {
    function distribute() external returns ( bool );
}

contract Staking is OwnableUpgradeable, ReentrancyGuardUpgradeable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public UDO;
    address public sUDO;

    struct Epoch {
        uint length;
        uint number;
        uint endBlock;
        uint distribute;
    }
    Epoch public epoch;

    address public distributor;
    
    address public locker;
    uint public totalBonus;
    
    address public warmupContract;
    uint public warmupPeriod;

    /* ======== INITIALIZATION ======== */
    
    function initialize(
        address _UDO, 
        address _sUDO, 
        uint _epochLength,
        uint _firstEpochNumber,
        uint _firstEpochBlock
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        require( _UDO != address(0) );
        UDO = _UDO;
        require( _sUDO != address(0) );
        sUDO = _sUDO;
        
        epoch = Epoch({
            length: _epochLength,
            number: _firstEpochNumber,
            endBlock: _firstEpochBlock,
            distribute: 0
        });
    }

    struct Claim {
        uint deposit;
        uint gons;
        uint expiry;
        bool lock; // prevents malicious delays
    }
    mapping( address => Claim ) public warmupInfo;

    /**
        @notice stake UDO to enter warmup
        @param _amount uint
        @return bool
     */
    function stake( uint _amount, address _recipient ) external nonReentrant returns ( bool ) {
        require(_recipient != address(0), "Recipient undefined");
        
        Claim memory info = warmupInfo[ _recipient ];
        require( !info.lock, "Deposits for account are locked" );

        rebase();
        
        IERC20( UDO ).safeTransferFrom( msg.sender, address(this), _amount );

        if (warmupPeriod > 0) {
            warmupInfo[ _recipient ] = Claim ({
                deposit: info.deposit.add( _amount ),
                gons: info.gons.add( IsUDO( sUDO ).gonsForBalance( _amount ) ),
                expiry: epoch.number.add( warmupPeriod ),
                lock: false
            });
        
            IERC20( sUDO ).safeTransfer( warmupContract, _amount );
        } else {
            IERC20( sUDO ).safeTransfer(_recipient, _amount);
        }
        
        return true;
    }

    /**
        @notice retrieve sUDO from warmup
        @param _recipient address
     */
    function claim ( address _recipient ) public nonReentrant {
        Claim memory info = warmupInfo[ _recipient ];
        if ( info.gons > 0 && epoch.number >= info.expiry && info.expiry != 0 ) {
            delete warmupInfo[ _recipient ];
            IWarmup( warmupContract ).retrieve( _recipient, IsUDO( sUDO ).balanceForGons( info.gons ) );
        }
    }

    /**
        @notice forfeit sUDO in warmup and retrieve UDO
     */
    function forfeit() external nonReentrant {
        Claim memory info = warmupInfo[ msg.sender ];
        if (info.gons > 0) {
            delete warmupInfo[ msg.sender ];

            IWarmup( warmupContract ).retrieve( address(this), IsUDO( sUDO ).balanceForGons( info.gons ) );
            IERC20( UDO ).safeTransfer( msg.sender, info.deposit );
        }
    }

    /**
        @notice prevent new deposits to address (protection from malicious activity)
     */
    function toggleDepositLock() external {
        warmupInfo[ msg.sender ].lock = !warmupInfo[ msg.sender ].lock;
    }

    /**
        @notice redeem sUDO for UDO
        @param _amount uint
        @param _trigger bool
     */
    function unstake( uint _amount, bool _trigger ) external nonReentrant {
        require(_amount <= contractBalance(), "Insufficient contract balance");
        if ( _trigger ) {
            rebase();
        }
        IERC20( sUDO ).safeTransferFrom( msg.sender, address(this), _amount );
        IERC20( UDO ).safeTransfer( msg.sender, _amount );
    }

    /**
        @notice returns the sUDO index, which tracks rebase growth
        @return uint
     */
    function index() public view returns ( uint ) {
        return IsUDO( sUDO ).index();
    }

    /**
        @notice trigger rebase if epoch over
     */
    function rebase() public {
        if( epoch.endBlock <= block.number ) {
            IsUDO( sUDO ).rebase( epoch.distribute, epoch.number );

            epoch.endBlock = epoch.endBlock.add( epoch.length );
            epoch.number++;
            
            if ( distributor != address(0) ) {
                IDistributor( distributor ).distribute();
            }

            uint balance = contractBalance();
            uint staked = IsUDO( sUDO ).circulatingSupply();

            if( balance <= staked ) {
                epoch.distribute = 0;
            } else {
                epoch.distribute = balance.sub( staked );
            }
        }
    }

    /**
        @notice returns contract UDO holdings, including bonuses provided
        @return uint
     */
    function contractBalance() public view returns ( uint ) {
        return IERC20( UDO ).balanceOf( address(this) ).add( totalBonus );
    }

    /**
        @notice provide bonus to locked staking contract
        @param _amount uint
     */
    function giveLockBonus( uint _amount ) external {
        require( msg.sender == locker );
        totalBonus = totalBonus.add( _amount );
        IERC20( sUDO ).safeTransfer( locker, _amount );
    }

    /**
        @notice reclaim bonus from locked staking contract
        @param _amount uint
     */
    function returnLockBonus( uint _amount ) external {
        require( msg.sender == locker );
        totalBonus = totalBonus.sub( _amount );
        IERC20( sUDO ).safeTransferFrom( locker, address(this), _amount );
    }

    enum CONTRACTS { DISTRIBUTOR, WARMUP, LOCKER }

    /**
        @notice sets the contract address for LP staking
        @param _contract address
     */
    function setContract( CONTRACTS _contract, address _address ) external onlyOwner() {
        if( _contract == CONTRACTS.DISTRIBUTOR ) { // 0
            distributor = _address;
        } else if ( _contract == CONTRACTS.WARMUP ) { // 1
            require( warmupContract == address( 0 ), "Warmup cannot be set more than once" );
            warmupContract = _address;
        } else if ( _contract == CONTRACTS.LOCKER ) { // 2
            require( locker == address(0), "Locker cannot be set more than once" );
            locker = _address;
        }
    }
    
    /**
     * @notice set warmup period for new stakers
     * @param _warmupPeriod uint
     */
    function setWarmup( uint _warmupPeriod ) external onlyOwner() {
        warmupPeriod = _warmupPeriod;
    }
}