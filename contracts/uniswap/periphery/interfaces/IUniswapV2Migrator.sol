pragma solidity >=0.5.0;

// SPDX-License-Identifier: GPL-3.0-or-later

interface IUniswapV2Migrator {
    function migrate(address token, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external;
}
