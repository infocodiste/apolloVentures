// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./LaunchpadPresale.sol";

contract LaunchpadFactoryClone is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    address public router;
    address immutable tokenImplementation;
    address public stakingContract;
    address public feeAddress;

    uint256 public liquidityPercentLimit = 5000;
    uint256 public createFee;

    mapping (address => address) public CloneAddressOf;

    event CreateLaunch(address indexed token, LaunchpadPresale.Parameters par, LaunchpadPresale.WhitelistParameters wpar, 
        LaunchpadPresale.VestingParameters vpar, uint256 tokens, uint256 raisedFee, uint256 influencerFee);
    constructor(address _router, address _feeAddress, uint256 _createFee) {
        router = _router;
        feeAddress = _feeAddress;
        tokenImplementation = address(new LaunchpadPresale());
        createFee = _createFee;
    }

    /**
     * @dev Sets staking contract address
     */
    function setStakingContract(address _stakingContract) external onlyOwner {
        stakingContract = _stakingContract;
    }

    /**
     * @dev Sets fee collector address
     */
    function setFeeAddress(address _feeAddress) external onlyOwner {
        feeAddress = _feeAddress;
    }

    /**
     * @dev To set liquidity percent limit
     */
    function setLiquidityPercentLimit(uint256 _liquidityPercentLimit) external onlyOwner {
        liquidityPercentLimit = _liquidityPercentLimit;
    }

    /**
     * @dev To set create fee
     */
    function setCreateFee(uint256 _createFee) external onlyOwner {
        createFee = _createFee;
    }

    /**
     * @param presaleRate: 1 BNB = ? Tokens in WEI
     * @param hardcap: ? BNB in WEI
     * @param liquidityPercent: ? % multiplied with 100 e.g. Fir 50% pass 5000
     * @param listingRate: 1 BNB = ? Tokens in WEI (At the time of adding liquiding in Router)
     */
    function requiredTokens(uint256 presaleRate, uint256 hardcap, uint256 liquidityPercent, uint256 listingRate) 
    public pure returns (uint256 tokens) {
        uint256 tokensToBuyers = (hardcap * presaleRate) / 1 ether;
        uint256 tokensToLiquidity = (hardcap * liquidityPercent* listingRate) / 10000 ether;
        tokens = tokensToBuyers + tokensToLiquidity;
    }

    /**
     * @dev To create new launchpad presale contract
     */
    function createLaunch(address token, LaunchpadPresale.Parameters memory par, LaunchpadPresale.WhitelistParameters 
    memory wpar, LaunchpadPresale.VestingParameters memory vpar, uint256 raisedFee, uint256 influencerFee) public 
    payable nonReentrant whenNotPaused {
        require(msg.value >= createFee, "Fees are wrong");
        require(par.liquidityPercent >= liquidityPercentLimit, "Liquidity Percent Low");

        address clone = Clones.clone(tokenImplementation);
        LaunchpadPresale(clone).initialize(
            feeAddress,
            token,
            router,
            stakingContract,
            par,
            wpar,
            vpar,
            raisedFee,
            influencerFee
        );

        LaunchpadPresale(clone).transferOwnership(msg.sender);
        CloneAddressOf[token] = clone;

        uint256 tokens = requiredTokens(par.presaleRate, par.hardcap, par.liquidityPercent, par.listingRate);
        IERC20(token).safeTransferFrom(msg.sender, clone, tokens);

        emit CreateLaunch(token, par, wpar, vpar, tokens, raisedFee, influencerFee);
    }


    /**
     * @dev Withdraw BNB 
     */
    function withdraw(uint256 weiAmount, address to) external onlyOwner {
        require(address(this).balance >= weiAmount, "insufficient BNB balance");
        (bool sent, ) = payable(to).call{value: weiAmount}("");
        require(sent, "Failed to withdraw");
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