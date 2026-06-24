// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SCB World Cup Pari-Mutuel Yield-Bearing Pool
 * @notice Deposits are capped, zero-odds, and auto-routed to Aave V3 for yield generation.
 * Principal goes to winners, interest goes to the DAA treasury to cover operating costs.
 */

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IAavePool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

contract WorldCupPool {
    IERC20 public immutable usdcToken;
    IAavePool public immutable aavePool;
    address public immutable aUSDC;
    address public owner;

    uint256 public constant BET_AMOUNT = 100 * 10**6;
    uint256 public totalPrincipalPool;
    string public winningCountry;
    bool public isFinished;
    bool public isSettled;

    mapping(string => uint256) public countryTotalBets;
    mapping(string => uint256) public countryWinnerCount;
    mapping(address => mapping(string => bool)) public userBets;
    mapping(address => bool) public hasClaimed;

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

    function bet(string calldata country) external {
        require(!isFinished, "Betting phase has closed");
        require(!userBets[msg.sender][country], "Already placed a bet on this country");

        require(usdcToken.transferFrom(msg.sender, address(this), BET_AMOUNT), "USDC transfer failed");

        userBets[msg.sender][country] = true;
        countryTotalBets[country] += BET_AMOUNT;
        countryWinnerCount[country] += 1;
        totalPrincipalPool += BET_AMOUNT;

        usdcToken.approve(address(aavePool), BET_AMOUNT);
        aavePool.supply(address(usdcToken), BET_AMOUNT, address(this), 0);

        emit BetPlaced(msg.sender, country, BET_AMOUNT);
    }

    function setWinner(string calldata _winningCountry) external onlyOwner {
        require(!isFinished, "Winner already declared");
        require(countryWinnerCount[_winningCountry] > 0, "No one betted on this country");

        winningCountry = _winningCountry;
        isFinished = true;

        emit WinnerDeclared(_winningCountry);
    }

    function settlePool(address daaTreasury) external onlyOwner {
        require(isFinished, "Tournament must be finished first");
        require(!isSettled, "Pool already settled");
        require(daaTreasury != address(0), "Invalid treasury address");

        uint256 totalAaveBalance = IERC20(aUSDC).balanceOf(address(this));
        require(totalAaveBalance >= totalPrincipalPool, "Insufficient pool balance");

        uint256 interestEarned = totalAaveBalance - totalPrincipalPool;

        aavePool.withdraw(address(usdcToken), type(uint256).max, address(this));

        if (interestEarned > 0) {
            require(usdcToken.transfer(daaTreasury, interestEarned), "Treasury transfer failed");
        }

        isSettled = true;
        emit PoolSettled(totalPrincipalPool, interestEarned);
    }

    function claimReward() external {
        require(isSettled, "Pool has not been settled yet");
        require(userBets[msg.sender][winningCountry], "You did not bet on the winning country");
        require(!hasClaimed[msg.sender], "Reward already claimed");

        hasClaimed[msg.sender] = true;

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
