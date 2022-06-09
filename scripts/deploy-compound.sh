#!/bin/bash


read -p "❓ Deploy Morpho-Compound's InterestRatesManager on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
	echo "Deploying Morpho-Compound's InterestRatesManager on ${NETWORK}..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" \
        --optimize contracts/compound/InterestRatesManager.sol:InterestRatesManager

    echo "🎉 InterestRatesManager deployed!"
fi


echo "---"
read -p "❓ Deploy Morpho-Compound's PositionsManager on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
	echo "Deploying Morpho-Compound's PositionsManager on ${NETWORK}..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" \
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
    read -p "           ${NETWORK}'s cETH address? " -r CETH_ADDRESS
    read -p "           ${NETWORK}'s wETH address? " -r WETH_ADDRESS

	echo "Initializing Morpho-Compound's Proxy on ${NETWORK} at ${MORPHO_PROXY_ADDRESS}, with 1 dustThreshold & 16 maxSortedUsers..."

    MAX_GAS_FOR_MATCHING=$(cast abi-encode "tuple(uint64,uint64,uint64,uint64)" 100000 100000 100000 100000)
	cast send --private-key "${DEPLOYER_PRIVATE_KEY}" "${MORPHO_PROXY_ADDRESS}" \
        0x34544040000000000000000000000000"${MORPHO_POSITIONS_MANAGER_ADDRESS:2}"000000000000000000000000"${MORPHO_INTEREST_RATES_MANAGER_ADDRESS:2}"000000000000000000000000"${COMPTROLLER_ADDRESS:2}""${MAX_GAS_FOR_MATCHING:2}"00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000010000000000000000000000000"${CETH_ADDRESS:2}"000000000000000000000000"${WETH_ADDRESS:2}"

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
        --optimize contracts/compound/Lens.sol:Lens \
        --constructor-args "${MORPHO_PROXY_ADDRESS}"

    echo "🎉 Lens deployed!"
fi


echo "---"
echo "🎉 Deployment completed!"
