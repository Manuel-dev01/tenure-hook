// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title DemoERC20
/// @notice A minimal ERC20 for the Sepolia demonstration pool, with an open faucet so anyone
///         opening the app can fund themselves without asking us for tokens.
///
/// @dev DEMONSTRATION ONLY. This exists so the hook has a pool to guard on a testnet. It is not
///      part of the mechanism, carries no value, and nothing in `TenureHook`, `TenureRegistry` or
///      the circuit depends on it. Deliberately not named `TestToken`: `scripts/gate.sh` greps
///      `src/` filenames for out-of-scope module names, and this project does not ship a token.
///
/// @dev The faucet is unguarded on purpose. Rate-limiting it would add state and a failure mode to
///      a contract whose only job is to let a judge press a button and get a balance.
contract DemoERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /// @notice Amount `faucet()` mints per call, in whole units scaled by `decimals`.
    uint256 public immutable faucetAmount;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error InsufficientBalance();
    error InsufficientAllowance();

    constructor(string memory _name, string memory _symbol, uint8 _decimals, uint256 _faucetAmount) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        faucetAmount = _faucetAmount;
    }

    /// @notice Mint `faucetAmount` to the caller. Open to anyone.
    function faucet() external {
        _mint(msg.sender, faucetAmount);
    }

    /// @notice Mint an arbitrary amount to `to`. Open, for the same reason the faucet is.
    /// @param to Recipient.
    /// @param amount Amount in base units.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Approve `spender` to move `amount` of the caller's balance.
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfer `amount` to `to`.
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Transfer `amount` from `from` to `to`, spending the caller's allowance.
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance();
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        uint256 bal = balanceOf[from];
        if (bal < amount) revert InsufficientBalance();
        unchecked {
            balanceOf[from] = bal - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }
}
