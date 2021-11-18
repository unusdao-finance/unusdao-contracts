// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IPriceCalculator {
    function priceOfBNB() external view returns(uint256);
    function priceOfToken(address token) external view returns(uint256);
}