pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICErc20, ICEth } from "./interfaces/ICompound.sol";


// TODO: add only proxy
// No constructor here as it will be called by a Proxy
// TODO resolve issue when token is not allowed anymore
// TODO beware that people can directly interact with this contract
contract CompoundModuleMultiAsset {

	mapping(address => bool) isOnComp;
	mapping(address => bool) tokenAllowed;
	mapping(address => mapping(address => address)) tokenToTokenModule; // DAI => compound => cDAI
	mapping(bytes32 => address) moduleAddress;
	mapping(address => bool) modules;
	mapping(address => mapping(address => LendingBalance)) lendingBalanceOf;
	mapping(address => mapping(address => BorrowingOperation)) borrowingOperations;
	mapping(address => mapping(address => uint256)) collateralBalanceOf;
	mapping(address => mapping(address => uint256)) borrowingBalanceOf;
	mapping(address => mapping(address => uint256)) stakingBalanceOf;
	address[] currentLenders;

	struct LendingBalance {
		uint256 total;
		uint256 used;
	}

	struct BorrowingOperation {
        uint256 timeBorrowed; // block number
        uint256 amountBorrowed;
        uint256 amountRepaid;
		address token; // ?
    }

	function stake(uint256 _amount, address _token) external {}

	function lend(uint256 _amount, address _token) external {
		require(tokenAllowed[_token], "");
        require(_amount > 0, "Amount cannot be 0");
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
		lendingBalanceOf[_token][msg.sender].total += _amount;
		// currentLenders.push(msg.sender);
	}

	function borrow(uint256 _amount, address _token) external {
		require(tokenAllowed[_token], "");

		// Verify that borrowers has enough collateral
        // TODO real collateral factor + conversion eth to dai
        uint256 COLLATERAL_FACTOR = 1;
        uint256 unusedCollateral = collateralBalanceOf[_token][msg.sender].total - collateralBalanceOf[_token][msg.sender].used;
        require(_amount < unusedCollateral * COLLATERAL_FACTOR, "");

		if (_token == "0x0") {
			ICEth token = ICEth(tokenToTokenModule[_token]);
		} else {
			ICErc20 token = ICErc20(tokenToTokenModule[_token]);
		}

        // Check if Leech has the cTokens for the borrowing
        // TODO: Verify multiplication, rounds
        uint256 availableTokenToBorrow = token.balanceOf(address(this)) * token.exchangeRateCurrent();
        require(_amount < availableTokenToBorrow, ""); // maybe take min of both?

        // Now Leech can take liquidity thanks to cTokens
        _findUnusedCTokenAndUse(_amount, _token);

        // Update used / unused collateral
		// TODO: check that
        collateralBalanceOf[_token][msg.sender].used += collateralBalanceOf[_token][msg.sender].usable;
		borrowingBalanceOf[_token][msg.sender] += _amount;

        // Signal that user has not been displaced to Comp (rare case but to prevent)
        isOnComp[msg.sender] = false;

        borrowingOperations[_token][msg.sender].timeBorrowed = block.timestamp;
        borrowingOperations[_token][msg.sender].amountBorrowed = _amount;
        borrowingOperations[_token][msg.sender].amountRepaid = 0;
        borrowingOperations[_token][msg.sender].asset = _token;

		require(_token.transfer(_amount), "");
	}

	function paybackAll(uint256 _amount, address _token) external {
		require(tokenAllowed[_token], "");
		require(_amount >= borrowingBalanceOf[_token][msg.sender], "need to payback all");
		IERC20(_token).transferFrom(msg.sender, address(this), _amount);
		_supplyErc20ToCompound(_token, _amount);
		_findUsedCTokensAndUnunse(RemainingLiquidityToUnuse=y);
		borrowingBalanceOf[_token][msg.sender] = 0;
		// TODO: transfer to msg.sender
	}

	// function cashOut(uint256 _amount, address _token) external {
	// 	require(tokenAllowed[_token], "");

	// }

	function cashOutAll(uint256 _amount, address _token) external {
		require(tokenAllowed[_token], "");
	}

	// function cashOutUnused(uint256 _amount, address _token) external {
	// 	require(tokenAllowed[_token], "");
	// }

	function provideCollateral(uint256 _amount, address _token) external {
		// address token = tokenToTokenModule[_token][moduleAddress[keccak256("Compound")]];
		// require(token != "0x0", "");
		// TODO: check if token is allowed.
		require(_amount > 0, "Amount cannot be 0");
		// TODO: approve
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        _supplyErc20ToCompound(_token, _amount);
        // We update the collateral balance of the message sender
        collateralBalanceOf[_token][msg.sender].total += _amount;
    }

	function redeemCollateral(uint256 _amount, address _token) external {
		require(isNotBorrowing(msg.sender), "You have to repay your borrowing to redeem collateral.");
		address cToken = tokenToTokenModule[_token][moduleAddress[keccak256("Compound")]];
		require(cToken != "0x0", "");
		require(_amount > 0, "Amount cannot be 0");
		// TODO: check if this is the right way to do that.
		uint256 amountToRedeem = collateralBalanceOf[_token][msg.sender].total;
        _redeemCErc20Tokens(amountToRedeem, false, cToken);
        // Amount of Tokens given by Compound calculation
        uint256 amountRedeemed = amountToRedeem * ICErc20(cToken).exchangeRateCurrent();
        // The sender does nott have any collateral anymore
        collateralBalanceOf[_token][msg.sender].total = 0;
        // Finally leech transfers it to the user
        IERC20(_token).transferFrom(address(this), msg.sender, amountRedeemed);
    }

	// TODO: write it
	function repayAll(uint256 _amount, address _token) external {
		uint256 COLLATERAL_FACTOR = 1;
        // On calcule le montant qui doit etre repay si on doit tout repay
        uint256 amountToRepay = _calculateAmountToRepay(msg.sender, _token);
        require(_amount >= amountToRepay, "");

		// TODO: handle of ether too

        // On prend l’ether du borrower
        // transfertfrom : Ne marche pas avec l eth, il faut faire ca dans l interface utilisateur
        // Le montant en ETH est envoyé en value
        // TODO: gérer la value en JavaScript

        // On actualise l’état des opérations (surement plus optimal de regrouper les trois dernières lignes de codes dans cette fonction)
        // borrowingOperations[msg.sender].time_borrowed = block.timestamp; // TODO: je ne sais pas trop ce qu'il faut changer ici
        borrowingOperations[msg.sender].amountBorrowed -= msg.value / COLLATERAL_FACTOR;
        borrowingOperations[msg.sender].amountRepaid += msg.value / COLLATERAL_FACTOR;

        // Les ETH sont remis sur compound pour récupérer les cETH
        _supplyEthToCompound(cEtherContract);
        //TODO transfer teth with it
        // We now get the cTokens back to litch:

        _redeemCEth(msg.value, false, cEtherContract); //Second argument false --> retrieve your asset based on an amount of the asset not the cToken (no conversion needed)
        // On alloue (virtuellement) les cTokens reçus
        //TODO : augmenter les maximaux car il y a de l'excédent de rewards
        _findUsedCTokenAndUnuse(msg.value);
	}

	function liquidate(address _borrower) external {
	}

	function _supplyEthToCompound(
        address _cToken
    ) internal payable returns (bool) {
        uint result = CEth(_cToken).mint{value: msg.value}();
        require(result == 0, "");
    }

	function _supplyErc20ToCompound(
        address _token,
        uint256 _amount
    ) internal returns (uint256) {
        // Create a reference to the underlying asset contract, like DAI.
        IERC20 underlying = IERC20(_token);
        // Create a reference to the corresponding cToken contract, like cDAI.
        ICErc20 cToken = ICErc20(tokenToTokenModule[_token][moduleAddress[keccak256("Compound")]]);
        // Approve transfer on the ERC20 contract.
        underlying.approve(address(cToken), _amount);
        // Mint cTokens.
        uint result = cToken.mint(_amount);
        return result;
    }

	function _redeemCErc20Tokens(
        uint256 _amount,
        bool _redeemType,
        address _cToken
    ) internal returns (bool) {
        // Create a reference to the corresponding cToken contract, like cDAI
        ICErc20 cToken = ICErc20(_cToken);

        uint256 result;
		// TODO: check here this is faulse
        if (_redeemType == true) {
            // Retrieve your asset based on a cToken amount
            result = cToken.redeem(_amount);
        } else {
            // Retrieve your asset based on an amount of the asset
            result = cToken.redeemUnderlying(_amount);
        }

        return true;
    }

	function _redeemCEth(
        uint256 _amount,
        bool _redeemType
    ) internal payable returns (bool) {
        // Create a reference to the corresponding cToken contract
		// TODO: address to change 0x0
        ICEth cToken = ICEth(tokenToTokenModule["0x0"][moduleAddress[keccak256("Compound")]]);

        uint256 result;
		// TODO: check here if this is faulse
        if (redeemType == true) {
            // Retrieve your asset based on a cToken amount
            result = cToken.redeem(_amount);
        } else {
            // Retrieve your asset based on an amount of the asset
            result = cToken.redeemUnderlying(_amount);
        }

        return true;
    }

	// TODO: can be public
	function _calculateAmountToRepay(address _borrower, address _token) internal returns(uint256) {
        uint256 amountToRepay = borrowingOperations[msg.sender].amountBorrowed - borrowingOperations[msg.sender].amountRepaid;
        return amountToRepay;
        // TODO: imitate compound with compounded interest
    }

	// TODO: can be a modifier
	function isNotBorrowing() private returns (bool){
        return (borrowingOperations[msg.sender].amountBorrowed == 0);
        // TODO: Verify that all borrowings have been repaid
    }

	function _findUnusedCTokensAndUse(uint256 _amount, address _token) internal {
		uint256 remainingLiquidityToUse = _amount;
		uint256 i;
		while (remainingLiquidityToUse > 0 && i < list.length) {
			address lenderAddress = currentLenders[i];

			// We calculate how much is unused=usable for this lender
			uint256 usable = lendingBalanceOf[_token][lenderAddress].total - lendingBalanceOf[_token][lenderAddress].used;
			if (usable > 0) {
				// We increase used balance of this lender by eihter the max the lender can use or the max we need to use
				lendingBalanceOf[_token][lenderAddress].used += min(usable, remainingLiquidityToUse);
				remainingLiquidityToUse -= usable;
			}
			i += 1;
		}
	}

	function _findUsedCTokensAndUnunse(uint256 _amount, address _token) internal {
		uint256 remainingLiquidityToUnuse = _amount;
		uint256 i = length(lenders);
		while (remainingLiquidityToUnuse > 0 && i < list.length ) {
			address lenderAddress = currentLenders[i];
			// We calculate how much is used=unusable for this lender
			uint256 unusable = lendingBalanceOf[_token][lenderAddress].used;

			if (unusable > 0) {
				// We decrease used balance of this lender by eihter the max the lender can unuse or the max we need to unuse
				lendingBalanceOf[_token][lenderAddress].used -= min(unusable, remainingLiquidityToUnuse);
				// Then we decrease the liquidity to find by how we just used
				remainingLiquidityToUnuse -= unusable;
			}

			i += 1;
		}
	}
}