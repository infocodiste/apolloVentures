// SPDX-License-Identifier: MIT

// Contract Under Development

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Staking is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;

    IERC20Metadata public MLMToken;
    IERC20Metadata public BUSDToken;

    uint256 public minStakePeriod;
    uint256 public soldPercentAllowed;
    uint256 public totalStaked;
    uint256 public RewardPaidout;
    uint256 public RewardAvailable;

    struct User {
        uint256 amount;
        uint256 pending;
        uint256 claimed;
        uint256 lastStakeTimestamp;
        uint256 requiredMLMBalance;
    }

    mapping (address => User) public userInfo;

    event Log (address indexed account, uint256 amount, uint256 timestamp, bool indexed txType);
    event Claim (address indexed account, uint256 reward, uint256 timestamp);


    constructor(address _MLMToken, address _BUSDToken, uint256 _minStakePeriod, uint256 _soldPercentAllowed) {
        MLMToken = IERC20Metadata(_MLMToken);
        BUSDToken = IERC20Metadata(_BUSDToken);
        minStakePeriod = _minStakePeriod;
        soldPercentAllowed = _soldPercentAllowed;
    }

    function setMLMToken(address _MLMToken) external onlyOwner {
        MLMToken = IERC20Metadata(_MLMToken);
    }

    function setBUSDToken(address _BUSDToken) external onlyOwner {
        BUSDToken = IERC20Metadata(_BUSDToken);
    }

    function setMinStakePeriod(uint256 _minStakePeriod) external onlyOwner {
        minStakePeriod = _minStakePeriod;
    }

    function setSoldPercentAllowed(uint256 _soldPercentAllowed) external onlyOwner {
        soldPercentAllowed = _soldPercentAllowed;
    }

    function fund(uint256 amount) external onlyOwner {
        RewardAvailable += amount;
        BUSDToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function stake(uint256 amount) public whenNotPaused nonReentrant {
        if (userInfo[msg.sender].lastStakeTimestamp == 0) {
            userInfo[msg.sender].lastStakeTimestamp = block.timestamp;
        }

        userInfo[msg.sender].amount += amount;
        totalStaked += amount;

        MLMToken.safeTransferFrom(msg.sender, address(this), amount);

        userInfo[msg.sender].requiredMLMBalance = ((MLMToken.balanceOf(msg.sender)) * (10000 - soldPercentAllowed))/10000;

        emit Log(msg.sender, amount, block.timestamp, true);
    }

    function unstake(uint256 amount) public nonReentrant {
        require(userInfo[msg.sender].amount >= amount, "Staked amount is less");
        require((MLMToken.balanceOf(msg.sender)) >= userInfo[msg.sender].requiredMLMBalance, "Sold over allowed");

        userInfo[msg.sender].amount -= amount;
        totalStaked -= amount;

        if (userInfo[msg.sender].amount <= 0) {
            userInfo[msg.sender].lastStakeTimestamp = 0;
        }

        MLMToken.safeTransfer(msg.sender, amount);

        userInfo[msg.sender].requiredMLMBalance = ((MLMToken.balanceOf(msg.sender)) * (10000 - soldPercentAllowed))/10000;

        emit Log(msg.sender, amount, block.timestamp, false);
    }

    function claim() public nonReentrant {
        require((block.timestamp - userInfo[msg.sender].lastStakeTimestamp) >= minStakePeriod, "Min Stake Period Required");
        require((MLMToken.balanceOf(msg.sender)) >= userInfo[msg.sender].requiredMLMBalance, "Sold over allowed");

        uint256 reward = userInfo[msg.sender].pending;
        userInfo[msg.sender].pending = 0;
        userInfo[msg.sender].claimed += reward;
        RewardPaidout += reward;
        RewardAvailable -= reward;
        BUSDToken.safeTransfer(msg.sender, reward);

        emit Claim(msg.sender, reward, block.timestamp);
    }

    function setRewards(address[] memory user, uint256[] memory amount) external onlyOwner {
        require(user.length == amount.length, "Length Mismatch");

        for(uint256 i=0; i < user.length; i++) {
            userInfo[user[i]].pending += amount[i];
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}