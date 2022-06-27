#!/bin/bash
set -euo pipefail # exit on error
export $(xargs < .env.local)


echo "---"
read -p "⚡❓ Initialize Morpho-Compound's Proxy on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
    read -p "           Morpho-Compound's Proxy address on ${NETWORK}? " -r MORPHO_PROXY_ADDRESS
    read -p "           Morpho-Compound's PositionsManager address on ${NETWORK}? " -r MORPHO_POSITIONS_MANAGER_ADDRESS
    read -p "           Morpho-Compound's InterestRatesManager address on ${NETWORK}? " -r MORPHO_INTEREST_RATES_MANAGER_ADDRESS
    read -p "           Compound's Comptroller address on ${NETWORK}? " -r COMPTROLLER_ADDRESS
    read -p "           Morpho-Compound's defaultMaxGasForMatching on ${NETWORK}? " -r DEFAULT_MAX_GAS_FOR_MATCHING
    read -p "           Morpho-Compound's dustThreshold on ${NETWORK}? " -r DUST_THRESHOLD
    read -p "           Morpho-Compound's maxSortedUsers on ${NETWORK}? " -r MAX_SORTED_USERS
    read -p "           ${NETWORK}'s cETH address? " -r CETH_ADDRESS
    read -p "           ${NETWORK}'s wETH address? " -r WETH_ADDRESS

	echo "Initializing Morpho-Compound's Proxy on ${NETWORK} at ${MORPHO_PROXY_ADDRESS}, with ${DEFAULT_MAX_GAS_FOR_MATCHING} defaultMaxGasForMatching, ${DUST_THRESHOLD} dustThreshold & ${MAX_SORTED_USERS} maxSortedUsers..."

    POSITIONS_MANAGERO_INTEREST_RATES_MANAGER_COMPTROLLER_ADDRESS=$(cast abi-encode "tuple(address,address,address)" "${MORPHO_POSITIONS_MANAGER_ADDRESS}" "${MORPHO_INTEREST_RATES_MANAGER_ADDRESS}" "${COMPTROLLER_ADDRESS}")
    DUST_THRESHOLD_MAX_SORTED_USERS=$(cast abi-encode "tuple(uint256,uint256)" "${DUST_THRESHOLD}" "${MAX_SORTED_USERS}")
    DEFAULT_MAX_GAS_FOR_MATCHING=$(cast abi-encode "tuple(uint64,uint64,uint64,uint64)" "${DEFAULT_MAX_GAS_FOR_MATCHING}" "${DEFAULT_MAX_GAS_FOR_MATCHING}" "${DEFAULT_MAX_GAS_FOR_MATCHING}" "${DEFAULT_MAX_GAS_FOR_MATCHING}")
    CETH_WETH_ADDRESS=$(cast abi-encode "tuple(address,address)" "${CETH_ADDRESS}" "${WETH_ADDRESS}")

    cast send --private-key "${DEPLOYER_PRIVATE_KEY}" \
        "${MORPHO_PROXY_ADDRESS}" \
        0x34544040"${POSITIONS_MANAGERO_INTEREST_RATES_MANAGER_COMPTROLLER_ADDRESS:2}""${DEFAULT_MAX_GAS_FOR_MATCHING:2}""${DUST_THRESHOLD_MAX_SORTED_USERS:2}""${CETH_WETH_ADDRESS:2}"

    echo "🎉 Morpho Proxy initialized!"
fi


echo "---"
read -p "⚡❓ Initialize Morpho-Compound's RewardsManager Proxy on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
    read -p "           Morpho-Compound's RewardsManager Proxy address on ${NETWORK}? " -r MORPHO_REWARDS_MANAGER_PROXY_ADDRESS
    read -p "           Morpho-Compound's Proxy address on ${NETWORK}? " -r MORPHO_PROXY_ADDRESS

	echo "Initializing Morpho-Compound's RewardsManager Proxy on ${NETWORK} at ${MORPHO_REWARDS_MANAGER_PROXY_ADDRESS}..."

    cast send --private-key "${DEPLOYER_PRIVATE_KEY}" \
        "${MORPHO_REWARDS_MANAGER_PROXY_ADDRESS}" \
        "initialize(address)" "${MORPHO_PROXY_ADDRESS}"
    cast send --private-key "${DEPLOYER_PRIVATE_KEY}" \
        "${MORPHO_PROXY_ADDRESS}" \
        "setRewardsManager(address)" "${MORPHO_REWARDS_MANAGER_PROXY_ADDRESS}"

    echo "🎉 RewardsManager Proxy initialized!"
fi


echo "---"
read -p "⚡❓ Initialize Morpho-Compound's Lens Proxy on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
    read -p "           Morpho-Compound's Lens Proxy address on ${NETWORK}? " -r MORPHO_REWARDS_MANAGER_PROXY_ADDRESS
    read -p "           Morpho-Compound's Proxy address on ${NETWORK}? " -r MORPHO_PROXY_ADDRESS

	echo "Initializing Morpho-Compound's Lens Proxy on ${NETWORK} at ${MORPHO_REWARDS_MANAGER_PROXY_ADDRESS}..."

    cast send --private-key "${DEPLOYER_PRIVATE_KEY}" \
        "${MORPHO_REWARDS_MANAGER_PROXY_ADDRESS}" \
        "initialize(address)" "${MORPHO_PROXY_ADDRESS}"

    echo "🎉 Lens Proxy initialized!"
fi


echo "---"
echo "🎉 Initialization completed!"
