// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./../interfaces.sol";

interface IStaking {
    function whitelist(address account) external returns (bool);
}

contract LaunchpadPresale is Initializable, ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    address public feeAddress;
    
    IERC20 public token;
    IUniswapV2Router02 public router;
    IStaking public stakingContract;

    uint256 public totalBought;
    uint256 public totalClaimed;
    uint256 public liqidityLockedTill;
    uint256 public influencerFee;
    uint256 public raisedFee;

    bool public fail;
    bool public isFinalized;

    struct Parameters {
        uint256 presaleRate;
        uint256 softcap;
        uint256 hardcap;
        uint256 minBuy;
        uint256 maxBuy;
        uint256 startTime;
        uint256 endTime;
        uint256 liquidityPercent;
        uint256 lockingPeriod;
        uint256 listingRate;
    }

    struct VestingParameters {
        bool vesting;
        uint256 vestingFirstRelease;  // In percentage multiplied with 100
        uint256 vestingCyclePeriod;
        uint256 vestingCycleRelease;  // In percentage multiplied with 100
        uint256 vestingCycles;
    }

    struct WhitelistParameters {
        bool whitelist;
        uint256 duration;
        uint256 minBuy;
        uint256 maxBuy;
    }

    Parameters public par;
    WhitelistParameters public wpar;
    VestingParameters public vpar;

    mapping (address => bool) public whitelist;
    mapping (address => uint256) public wbought;
    mapping (address => uint256) public bought;
    mapping (address => uint256) public claimed;

    event Buy(address indexed account, uint256 amount);
    event Claim(address indexed account, uint256 tokens);
    event Withdraw(address indexed account, uint256 amount);
    event Success(address token, uint256 amountToLiquidity, uint256 tokensToLiquidity, uint256 unsold);
    event Fail(address indexed token);

    /**
     * @dev Initializing contract with parameters
     */
    function initialize(address _feeAddress, address _token, address _router, address _stakingContract, 
    Parameters memory _par, WhitelistParameters memory _wpar, VestingParameters memory _vpar, uint256 _raisedFee, 
    uint256 _influencerFee) public initializer {
        require(_par.softcap >= (_par.hardcap / 2), "Softcap must be >= 50% of Hardcap");

        _transferOwnership(_msgSender());

        feeAddress = _feeAddress;
        token = IERC20(_token);
        router = IUniswapV2Router02(_router);
        stakingContract = IStaking(_stakingContract);
        par = _par;
        wpar = _wpar;
        vpar = _vpar;
        raisedFee = _raisedFee;
        influencerFee = _influencerFee;
    }

    /**
     * @dev Adding accounts to whitelist if whitelist tier is active
     * @notice gas is propotional to array size
     * @param account: array of addresses to whitelist
     */
    function addToWhitelist(address[] memory account) external onlyOwner {
        require(wpar.whitelist == true, "Whitelist is not active");

        for(uint256 i=0; i < account.length; i++) {
            whitelist[account[i]] = true;
        }
    }

    /**
     * @dev To whitelist yourself through staking
     */
    function getWhitelisted() public {
        require(stakingContract.whitelist(msg.sender));
        whitelist[msg.sender] = true;
    }

    /**
     * @dev To buy tokens
     */
    function buy() public payable nonReentrant whenNotPaused {
        require(block.timestamp >= par.startTime && block.timestamp < par.endTime, "Sale Not Active");

        if (wpar.whitelist == true && block.timestamp < (par.startTime + wpar.duration)) {
            require(whitelist[msg.sender] == true, "You are not Whitelisted");

            require(wbought[msg.sender] + msg.value >= wpar.minBuy && wbought[msg.sender] + msg.value <= wpar.maxBuy, 
                "Whitelist: Can't Buy");

            wbought[msg.sender] += msg.value;
            totalBought += msg.value;
        } else {
            require(bought[msg.sender] + msg.value>= par.minBuy && bought[msg.sender] + msg.value <= par.maxBuy, 
                "Can't Buy");

            bought[msg.sender] += msg.value;
            totalBought += msg.value;
        }

        emit Buy(msg.sender, msg.value);
    }

    /**
     * @dev calculates amount of tokens as per presale rate
     * @param amount: BNB amount
     */
    function calculateTokens(uint256 amount) public view returns(uint256 tokens) {
        tokens = (par.presaleRate * amount) / 1 ether;
    }

    /**
     * @dev Finalizing/Ending the Presale Launch
     * Adding liquidity as per percentage provided
     * Returning remaining BNB to owner
     * Unsold tokens are returned to owner
     * If fails then return all tokens to owner 
     */
    function finalize() external onlyOwner {
        require(block.timestamp > par.endTime, "Sale is not ended");

        if ((block.timestamp - par.endTime) < 300) {   // 259200 == 72 hours
            require(msg.sender == owner(), "Not Owner");
        }

        isFinalized = true;
        
        if (totalBought > par.softcap) {
            fail = false;

            uint256 raisedFeeAmount = percent(totalBought, raisedFee);
            uint256 feesToPay = raisedFeeAmount + influencerFee;

            (bool sentFee, ) = payable(feeAddress).call{value: feesToPay}("");
            require(sentFee, "Fees transfer failed");

            // Adding Liquidity
            uint256 amountToLiquidity = (address(this).balance * par.liquidityPercent) / 10000;
            uint256 tokensToLiquidity = (par.listingRate * amountToLiquidity) / 1 ether;

            addLiquidity(tokensToLiquidity, amountToLiquidity);

            // Returning Remaining BNB To Owner
            if(address(this).balance > 0) {
                (bool sent, ) = payable(owner()).call{value: address(this).balance}("");
                require(sent, "Remaining BNB Transfer Failed");
            }

            // Transferring Unsold Tokens to Owner or Burning
            uint256 unsold = (token.balanceOf(address(this))) - (calculateTokens(totalBought));

            if (unsold > 0) {
                token.safeTransfer(owner(), unsold);
            }

            emit Success(address(token), amountToLiquidity, tokensToLiquidity, unsold);
            
        } else {
            fail = true;

            // Transferring All Tokens to Owner
            token.safeTransfer(owner(), token.balanceOf(address(this)));

            emit Fail(address(token));
        }
    }

    /**
     * @dev When Presale Launch Fails 
     * Users will be able to withdraw their BNB back
     */
    function withdraw() external nonReentrant {
        require(fail==true, "Can't Withdraw");
        
        uint256 amount = wbought[msg.sender] + bought[msg.sender];

        if (amount > 0) {
            wbought[msg.sender] = 0;
            bought[msg.sender] = 0;
            (bool sent, ) = payable(msg.sender).call{value: amount}("");
            require(sent, "Failed to withdraw");
        }

        emit Withdraw(msg.sender, amount);
    }

    /**
     * @dev Returns pending amount of tokens for an account
     * @param account: address of account
     */
    function pendingClaim(address account) public view returns(uint256 tokens) {
        if (block.timestamp > par.endTime) {
            uint256 ubought = calculateTokens(wbought[account] + bought[account]);
            uint256 cycles;

            if (vpar.vesting) {
                if (vpar.vestingCyclePeriod > 0) {
                    cycles = (block.timestamp - par.endTime) / vpar.vestingCyclePeriod;

                    if (cycles > vpar.vestingCycles) {
                        cycles = vpar.vestingCycles;
                    }
                }
                
                tokens += (ubought * vpar.vestingFirstRelease) / 10000;

                if (cycles > 0) {
                    tokens += (ubought * vpar.vestingCycleRelease * cycles) / 10000;
                }
            } else {
                tokens = ubought;
            }

            tokens -= claimed[account];
        }
    }

    /**
     * @dev To claim tokens
     */
    function claim() public nonReentrant {
        uint256 tokens = pendingClaim(msg.sender);

        if (tokens > 0) {
            token.safeTransfer(msg.sender, tokens);

            claimed[msg.sender] += tokens;
        }

        emit Claim(msg.sender, tokens);
    }

    /**
     * @dev To unlock and claim locked LP
     */
    function unlockLiquidity() external onlyOwner {
        require(block.timestamp > liqidityLockedTill, "Liquidity Locking Period is not Over");

        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        address pair = factory.getPair(address(token), router.WETH());
        uint256 LPBalance = IERC20(pair).balanceOf(address(this));

        IERC20(pair).safeTransfer(owner(), LPBalance);
    }

    /**
     * @dev To add liquidity 
     * @param tokensToLiquidity: tokens to add in liquidity
     * @param amountToLiquidity: BNB to add in liquidity
     */
    function addLiquidity(uint256 tokensToLiquidity, uint256 amountToLiquidity) private {
        token.safeApprove(address(router), tokensToLiquidity);

        router.addLiquidityETH{value: amountToLiquidity}(
            address(token),
            tokensToLiquidity,
            0,
            0,
            address(this),
            block.timestamp
        );

        liqidityLockedTill = block.timestamp + par.lockingPeriod;
    }

    /**
     * @dev Calculates percentage with two decimal support.
     */    
    function percent(uint256 amount, uint256 fraction) public virtual pure returns(uint256) {
        return ((amount * fraction) / 10000);
    }

    /**
     * @dev To pause
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev To unpause
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}