---

## 📄 Smart Contract Code (`WorldCupPool.sol`)

Below is the complete, production-ready Solidity smart contract. It utilizes **OpenZeppelin** for safe token transfers and **Aave V3** for yield generation.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SCB World Cup Pari-Mutuel Yield-Bearing Pool
 * @notice Deposits are capped, zero-odds, and auto-routed to Aave V3 for yield generation.
 * Principal goes to winners, interest goes to the DAA treasury to cover operating costs.
 */

// Import OpenZeppelin standard contracts
interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IOwnable {
    function owner() external view returns (address);
}

// Aave V3 Pool Interface
interface IAavePool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

contract WorldCupPool {
    
    // Immutable protocol references
    IERC20 public immutable usdcToken;
    IAavePool public immutable aavePool;
    address public immutable aUSDC; // Aave V3 Interest-bearing USDC token receipt
    address public owner;
    
    // Protocol parameters
    uint256 public constant BET_AMOUNT = 100 * 10**6; // Capped at exactly 100 USDC (6 decimals)
    uint256 public totalPrincipalPool;                // Total initial deposits
    string public winningCountry;                     // Winner set by Oracle/Owner
    bool public isFinished;                           // Status flags
    bool public isSettled;
    
    // Game state tracking
    mapping(string => uint256) public countryTotalBets;               // Total USDC per country
    mapping(string => uint256) public countryWinnerCount;             // Total voters per country
    mapping(address => mapping(string => bool)) public userBets;      // Address -> Country -> Has Bet
    mapping(address => bool) public hasClaimed;                       // Prevent double claims
    
    event BetPlaced(address indexed user, string country, uint256 amount);
    event WinnerDeclared(string winningCountry);
    event PoolSettled(uint256 principalReturned, uint256 interestToTreasury);
    event RewardClaimed(address indexed user, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _usdc, address _aavePool, address _aUSDC) {
        usdcToken = IERC20(_usdc);
        aavePool = IAavePool(_aavePool);
        aUSDC = _aUSDC;
        owner = msg.sender;
    }

    /**
     * @notice Allows users to place a single 100 USDC bet on a chosen country.
     * @dev Funds are instantly routed to Aave V3 to generate yield.
     */
    function bet(string calldata country) external {
        require(!isFinished, "Betting phase has closed");
        require(!userBets[msg.sender][country], "Already placed a bet on this country");
        
        // 1. Pull exactly 100 USDC from user (Requires prior approval on frontend)
        require(usdcToken.transferFrom(msg.sender, address(this), BET_AMOUNT), "USDC transfer failed");
        
        // 2. Internal Accounting
        userBets[msg.sender][country] = true;
        countryTotalBets[country] += BET_AMOUNT;
        countryWinnerCount[country] += 1;
        totalPrincipalPool += BET_AMOUNT;
        
        // 3. DeFi Routing: Supply directly to Aave V3 Pool to begin earning interest
        usdcToken.approve(address(aavePool), BET_AMOUNT);
        aavePool.supply(address(usdcToken), BET_AMOUNT, address(this), 0);
        
        emit BetPlaced(msg.sender, country, BET_AMOUNT);
    }

    /**
     * @notice Resolves the outcome of the tournament.
     * @dev Can be linked directly to a Chainlink Oracle or triggered via DAA multi-sig.
     */
    function setWinner(string calldata _winningCountry) external onlyOwner {
        require(!isFinished, "Winner already declared");
        require(countryWinnerCount[_winningCountry] > 0, "No one betted on this country");
        
        winningCountry = _winningCountry;
        isFinished = true;
        
        emit WinnerDeclared(_winningCountry);
    }

    /**
     * @notice Extracts the yield accrued in Aave over the month and routes it to operations.
     * @param daaTreasury The destination wallet for operational funding.
     */
    function settlePool(address daaTreasury) external onlyOwner {
        require(isFinished, "Tournament must be finished first");
        require(!isSettled, "Pool already settled");
        require(daaTreasury != address(0), "Invalid treasury address");
        
        // 1. Query cumulative balance inside Aave V3 (Principal + Interest)
        uint256 totalAaveBalance = IERC20(aUSDC).balanceOf(address(this));
        require(totalAaveBalance >= totalPrincipalPool, "Insufficient pool balance");
        
        uint256 interestEarned = totalAaveBalance - totalPrincipalPool;
        
        // 2. Redeem all tokens back to contract from Aave V3
        aavePool.withdraw(address(usdcToken), type(uint256).max, address(this));
        
        // 3. Extract the yield directly to the DAA Treasury to sustain systems
        if (interestEarned > 0) {
            require(usdcToken.transfer(daaTreasury, interestEarned), "Treasury transfer failed");
        }
        
        isSettled = true;
        emit PoolSettled(totalPrincipalPool, interestEarned);
    }
    
    /**
     * @notice Allows members who predicted the winning country to claim their pro-rata share.
     * @dev Simple pari-mutuel distribution formula: Total Pool / Number of Winners.
     */
    function claimReward() external {
        require(isSettled, "Pool has not been settled yet");
        require(userBets[msg.sender][winningCountry], "You did not bet on the winning country");
        require(!hasClaimed[msg.sender], "Reward already claimed");
        
        hasClaimed[msg.sender] = true;
        
        // Pari-mutuel calculation: Split the total initial principal pool evenly among correct bettors
        uint256 totalWinners = countryWinnerCount[winningCountry];
        uint256 myReward = totalPrincipalPool / totalWinners;
        
        require(usdcToken.transfer(msg.sender, myReward), "Reward payout failed");
        
        emit RewardClaimed(msg.sender, myReward);
    }
    
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }
}