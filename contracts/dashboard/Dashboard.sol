// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../library/SafeMath.sol";
import "../library/SafeDecimal.sol";
import "../interfaces/IsUDO.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPriceCalculator.sol";
import "../interfaces/IPancakePair.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IBondCalculator {
  function valuation( address pair_, uint amount_ ) external view returns ( uint _value );
}

struct Bond {
    uint payout; // UDO remaining to be paid
    uint vesting; // Blocks left to vest
    uint lastBlock; // Last interaction
    uint pricePaid; // In BUSD, for front end viewing
}

interface IBondDespository {
    function principle() external view returns(address);
    function bondPriceInUSD() external view returns(uint256);
    function maxPayout() external view returns (uint256);
    function standardizedDebtRatio() external view returns (uint256);
    function bondInfo(address _depositor) external view returns (Bond memory);
    function pendingPayoutFor(address _depositor) external view returns (uint pendingPayout_);
    function payoutFor(uint _value) external view returns (uint256);
}

struct Epoch {
    uint length;
    uint number;
    uint endBlock;
    uint distribute;
}

interface IStaking {
    function epoch() external view returns(Epoch memory);
}

interface ITreasury {
    function valueOf( address _token, uint _amount ) external view returns (uint value_);
}

contract Dashboard is OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeDecimal for uint256;

    address public UDO;
    address public sUDO;
    address public staking;
    address public treasury;

    bytes32 public constant CAKE_LP = keccak256("Cake-LP");
    bytes32 public constant BSW_LP = keccak256("BSW-LP");

    struct Bonds {
        address bond;
        bool enable;
        bool isLP;
    }

    Bonds[] public bonds;

    IPriceCalculator public priceCalculator;
    IBondCalculator public bondCalculator;

    address public BUSD;

    function initialize(
        address _UDO,
        address _sUDO,
        address _BUSD,
        address _staking,
        address _treasury,
        address _priceCalculator,
        address _bondCalculator
    ) external initializer {
        require(_UDO != address(0));
        require(_sUDO != address(0));
        require(_staking != address(0));
        require(_treasury != address(0));
        require(_priceCalculator != address(0));
        require(_bondCalculator != address(0));

        __Ownable_init();

        UDO = _UDO;
        sUDO = _sUDO;
        BUSD = _BUSD;
        staking = _staking;
        treasury = _treasury;
        priceCalculator = IPriceCalculator(_priceCalculator);
        bondCalculator = IBondCalculator(_bondCalculator);
    }

    function bondsLength() external view returns(uint256) {
        return bonds.length;
    }

    function setStaking(address _staking) external onlyOwner {
        require( _staking != address(0) );
        staking = _staking;
    }

    function setTreasury(address _treasury) external onlyOwner {
        require( _treasury != address(0) );
        treasury = _treasury;
    }

    function setPriceCalculator(address _priceCalculator) external onlyOwner {
        require( _priceCalculator != address(0) );
        priceCalculator = IPriceCalculator(_priceCalculator);
    }

    function setBondCalculator(address _bondCalculator) external onlyOwner {
        require(_bondCalculator != address(0));
        bondCalculator = IBondCalculator(_bondCalculator);
    }

    function setBonds(address _bond, bool _enable) external onlyOwner {
        require( _bond != address(0) );
        uint256 length = bonds.length;
        for (uint256 i = 0; i < length; ++i) {
            if (bonds[i].bond == _bond) {
                bonds[i].enable = _enable;
                return;
            }
        }

        address token = IBondDespository(_bond).principle();
        bytes32 symbol = keccak256(abi.encodePacked(IERC20(token).symbol()));
        bonds.push( Bonds({
            bond: _bond,
            enable: _enable,
            isLP: (symbol == CAKE_LP || symbol == BSW_LP) ? true : false
        }));
    }

    function setBUSD(address _BUSD) external onlyOwner {
        require(_BUSD != address(0));
        BUSD = _BUSD;
    }

    function marketCap() public view returns(uint256) {
        uint256 totalSupply = totalSupply();
        uint256 price = priceOfUDO();
        return price.mul(totalSupply).div(1e18);
    }

    function priceOfUDO() public view returns(uint256) {
        return priceCalculator.priceOfToken(UDO);
    }

    function totalSupply() public view returns(uint256) {
        return IERC20(UDO).totalSupply().mul(1e9);
    }

    function totalLocked() public view returns(uint256 amount) {
        amount = IsUDO(sUDO).circulatingSupply().mul(1e9);
    }

    function currentIndex() public view returns(uint256) {
        return IsUDO(sUDO).index().mul(1e9);
    }

    struct BondsInfo {
        address bond;
        uint256 mv;
        uint256 rfv;
        uint256 pol;
        uint256 price;
    }

    function bondsInfo() public view returns(BondsInfo[] memory info, uint256 mv, uint256 rfv) {
        Bonds[] memory _bonds = bonds;
        uint256 length = _bonds.length;
        uint256 count = 0;
        for (uint256 i = 0; i < length; ++i) {
            if (_bonds[i].enable == false) {
                continue;
            }
            count++;
        }
        info = new BondsInfo[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < length; ++i) {
            if (_bonds[i].enable == false) {
                continue;
            }

            address bond = _bonds[i].bond;
            address token = IBondDespository(bond).principle();
            uint256 bal = IERC20(token).balanceOf(treasury);
            uint256 value = bal.mul(priceCalculator.priceOfToken(token)).div(1e18);
            info[j].bond = bond;
            info[j].mv = value;
            info[j].price = IBondDespository(bond).bondPriceInUSD();
            if (_bonds[i].isLP) {
                info[j].rfv = bondCalculator.valuation(token, bal).mul(1e9);
                uint256 totalAmount = IERC20(token).totalSupply();
                if (totalAmount > 0) {
                    info[j].pol = bal.mul(1e18).div(totalAmount);
                } else {
                    info[j].pol = 0;
                }
            } else {
                info[j].rfv = value;
                info[j].pol = 0;
            }

            mv += info[j].mv;
            rfv += info[j].rfv;
            ++j;
        }

        if (length == 1) {
            uint256 bal = IERC20(BUSD).balanceOf(treasury);
            uint256 value = bal.mul(priceCalculator.priceOfToken(BUSD)).div(1e18);
            mv += value;
            rfv += value;
        }
    }

    function getNextReward() public view returns(uint256) {
        return IStaking(staking).epoch().distribute.mul(1e9);
    }

    function unusInfo() public view returns(
        uint256 udoPrice, 
        uint256 udoTotalSupply, 
        uint256 index,
        uint256 mv,
        uint256 rfv,
        uint256 udoTotalLocaked,
        uint256 nextReward,
        BondsInfo[] memory info) 
    {
        udoPrice = priceOfUDO();
        udoTotalSupply = totalSupply();
        index = currentIndex();
        (info, mv, rfv) = bondsInfo();
        udoTotalLocaked = totalLocked();
        nextReward = getNextReward();
    }

    function userStakingInfo(address _user) public view returns(
        uint256 balanceOfUDO,
        uint256 stakedBalance,
        uint256 nextRewardAmount,
        uint256 nextRewardYield,
        uint256 rebaseLeftBlock
    ) {
        balanceOfUDO = IERC20(UDO).balanceOf(_user).mul(1e9);
        stakedBalance = IERC20(sUDO).balanceOf(_user).mul(1e9);
        uint256 totalStaked = totalLocked();
        Epoch memory epoch = IStaking(staking).epoch();
        uint256 totalNextReward = epoch.distribute.mul(1e9);
        if (totalStaked > 0) {
            nextRewardAmount = totalNextReward.mul(stakedBalance).div(totalStaked);
            nextRewardYield = totalNextReward.mul(1e18).div(totalStaked);
        } else {
            nextRewardAmount = 0;
            nextRewardYield = 0;
        }

        if (epoch.endBlock > block.number) {
            rebaseLeftBlock = epoch.endBlock.sub(block.number);
        } else {
            rebaseLeftBlock = 0;
        }
    }

    function userBondInfo(address _user, address _bond, uint256 _amount) public view returns(
        uint256[] memory info
    ) {
        info = new uint256[](9);
        //bondPrice
        info[0] = IBondDespository(_bond).bondPriceInUSD();

        //udoPrice   
        info[1] = priceOfUDO();

        address token = IBondDespository(_bond).principle();
        //balance
        info[2] = IERC20(token).balanceOf(_user); 

        //balanceInUSD  
        info[3] = info[2].mul(priceCalculator.priceOfToken(token)).div(1e18); 

        //maxPayout
        info[4] = IBondDespository(_bond).maxPayout().mul(1e9);

        //debtRatio
        info[5] = IBondDespository(_bond).standardizedDebtRatio();

        //pendingRewards
        info[6] = IBondDespository(_bond).bondInfo(_user).payout.mul(1e9);

        //claimableRewards
        info[7] = IBondDespository(_bond).pendingPayoutFor(_user).mul(1e9);

        //payout
        if (_amount == 0) {
            info[8] = 0;
        } else {
            uint256 value = ITreasury(treasury).valueOf(token, _amount);
            info[8] = IBondDespository(_bond).payoutFor(value).mul(1e9);
        }
    }
}