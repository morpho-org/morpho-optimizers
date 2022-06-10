#!/bin/bash
set -euo pipefail # exit on error


read -p "❓ Deploy Morpho-Compound's InterestRatesManager on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
	echo "Deploying Morpho-Compound's InterestRatesManager on ${NETWORK}..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" \
        --contracts contracts/compound \
        --optimize contracts/compound/InterestRatesManager.sol:InterestRatesManager \
        --verify

    echo "🎉 InterestRatesManager deployed!"
fi


echo "---"
read -p "❓ Deploy Morpho-Compound's PositionsManager on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
	echo "Deploying Morpho-Compound's PositionsManager on ${NETWORK}..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" \
        --contracts contracts/compound \
        --optimize contracts/compound/PositionsManager.sol:PositionsManager

    echo "🎉 PositionsManager deployed!"
fi


echo "---"
read -p "❓ Deploy Morpho-Compound's Implementation on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
	echo "Deploying Morpho-Compound's Implementation on ${NETWORK}..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" \
        --contracts contracts/compound \
        --optimize contracts/compound/Morpho.sol:Morpho

    echo "🎉 Morpho Implementation deployed!"
fi


echo "---"
read -p "❓ Deploy Morpho-Compound's Proxy on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
    read -p "       Morpho-Compound's Implementation address? " -r MORPHO_IMPL_ADDRESS
    read -p "       Morpho-Compound's ProxyAdmin address on ${NETWORK}? " -r MORPHO_PROXY_ADMIN_ADDRESS

	echo "Deploying Morpho-Compound's Proxy on ${NETWORK} for Implementation at ${MORPHO_IMPL_ADDRESS}, owned by ${MORPHO_PROXY_ADMIN_ADDRESS}..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" \
        --contracts node_modules/@openzeppelin/contracts/proxy \
        --optimize node_modules/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy \
        --constructor-args "${MORPHO_IMPL_ADDRESS}" "${MORPHO_PROXY_ADMIN_ADDRESS}" ""

    echo "🎉 Morpho Proxy deployed!"
fi


echo "---"
read -p "❓ Initialize Morpho-Compound's Proxy on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
    read -p "           Morpho-Compound's Proxy address on ${NETWORK}? " -r MORPHO_PROXY_ADDRESS
    read -p "           Morpho-Compound's PositionsManager address on ${NETWORK}? " -r MORPHO_POSITIONS_MANAGER_ADDRESS
    read -p "           Morpho-Compound's InterestRatesManager address on ${NETWORK}? " -r MORPHO_INTEREST_RATES_MANAGER_ADDRESS
    read -p "           Compound's Comptroller address on ${NETWORK}? " -r COMPTROLLER_ADDRESS
    read -p "           Morpho-Compound's defaultMaxGasForMatching on ${NETWORK}? " -r DEFAULT_MAX_GAS_FOR_MATCHING
    read -p "           ${NETWORK}'s cETH address? " -r CETH_ADDRESS
    read -p "           ${NETWORK}'s wETH address? " -r WETH_ADDRESS

	echo "Initializing Morpho-Compound's Proxy on ${NETWORK} at ${MORPHO_PROXY_ADDRESS}, with 1 dustThreshold & 16 maxSortedUsers..."

    POSITIONS_MANAGERO_INTEREST_RATES_MANAGER_COMPTROLLER_ADDRESS=$(cast abi-encode "tuple(address,address,address)" "${MORPHO_POSITIONS_MANAGER_ADDRESS}" "${MORPHO_INTEREST_RATES_MANAGER_ADDRESS}" "${COMPTROLLER_ADDRESS}")
    DUST_THRESHOLD_MAX_SORTED_USERS=$(cast abi-encode "tuple(uint256,uint256)" 1 16)
    DEFAULT_MAX_GAS_FOR_MATCHING=$(cast abi-encode "tuple(uint64,uint64,uint64,uint64)" "${DEFAULT_MAX_GAS_FOR_MATCHING}" "${DEFAULT_MAX_GAS_FOR_MATCHING}" "${DEFAULT_MAX_GAS_FOR_MATCHING}" "${DEFAULT_MAX_GAS_FOR_MATCHING}")
    CETH_WETH_ADDRESS=$(cast abi-encode "tuple(address,address)" "${CETH_ADDRESS}" "${WETH_ADDRESS}")

    cast send --private-key "${DEPLOYER_PRIVATE_KEY}" "${MORPHO_PROXY_ADDRESS}" \
        0x34544040"${POSITIONS_MANAGERO_INTEREST_RATES_MANAGER_COMPTROLLER_ADDRESS:2}""${DEFAULT_MAX_GAS_FOR_MATCHING:2}""${DUST_THRESHOLD_MAX_SORTED_USERS:2}""${CETH_WETH_ADDRESS:2}"

    echo "🎉 Morpho Proxy initialized!"
fi


echo "---"
read -p "❓ Deploy Morpho-Compound's RewardsManager on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
    read -p "       Morpho-Compound's Proxy address on ${NETWORK}? " -r MORPHO_PROXY_ADDRESS

	echo "Deploying Morpho-Compound's RewardsManager for Proxy at ${MORPHO_PROXY_ADDRESS} on $NETWORK..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" \
        --contracts contracts/compound \
        --optimize contracts/compound/RewardsManager.sol:RewardsManager \
        --constructor-args "${MORPHO_PROXY_ADDRESS}"

    echo "🎉 RewardsManager deployed!"
fi


echo "---"
read -p "❓ Deploy Morpho-Compound's Lens on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
    read -p "       Morpho-Compound's Proxy address on ${NETWORK}? " -r MORPHO_PROXY_ADDRESS

	echo "Deploying Morpho-Compound's Lens for Proxy at ${MORPHO_PROXY_ADDRESS} on $NETWORK..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" \
        --contracts contracts/compound \
        --optimize contracts/compound/Lens.sol:Lens \
        --constructor-args "${MORPHO_PROXY_ADDRESS}"

    echo "🎉 Lens deployed!"
fi


echo "---"
echo "🎉 Deployment completed!"
