#!/bin/bash


read -p "Deploy Morpho-${PROTOCOL}'s InterestRatesManager on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
	echo "Deploying Morpho-${PROTOCOL}'s InterestRatesManager on ${NETWORK}..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" --optimize contracts/"${PROTOCOL}"/InterestRatesManager.sol:InterestRatesManager
fi


echo "---"
read -p "Deploy Morpho-${PROTOCOL}'s PositionsManager on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
	echo "Deploying Morpho-${PROTOCOL}\'s PositionsManager on ${NETWORK}..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" --optimize contracts/"${PROTOCOL}"/PositionsManager.sol:PositionsManager
fi


echo "---"
read -p "Deploy Morpho-${PROTOCOL}'s Implementation on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
	echo "Deploying Morpho-${PROTOCOL}'s Implementation on ${NETWORK}..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" --optimize contracts/"${PROTOCOL}"/Morpho.sol:Morpho
fi


echo "---"
read -p "Deploy Morpho-${PROTOCOL}'s Proxy on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
    read -p "       Morpho-${PROTOCOL}'s Implementation address? " -r MORPHO_IMPL_ADDRESS
    read -p "       Morpho-${PROTOCOL}'s ProxyAdmin address on ${NETWORK}? " -r MORPHO_PROXY_ADMIN_ADDRESS

	echo "Deploying Morpho-${PROTOCOL}'s Proxy on ${NETWORK} for Implementation at ${MORPHO_IMPL_ADDRESS}, owned by ${DEPLOYER_ADDRESS}..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" --contracts node_modules/@openzeppelin/contracts/proxy --optimize node_modules/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy --constructor-args "${MORPHO_IMPL_ADDRESS}" "${MORPHO_PROXY_ADMIN_ADDRESS}" ""
fi


echo "---"
read -p "Initialize Morpho-${PROTOCOL}'s Proxy on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
    read -p "           Morpho-${PROTOCOL}'s Proxy address on ${NETWORK}? " -r MORPHO_PROXY_ADDRESS
    read -p "           Morpho-${PROTOCOL}'s PositionsManager address on ${NETWORK}? " -r MORPHO_POSITIONS_MANAGER_ADDRESS
    read -p "           Morpho-${PROTOCOL}'s InterestRatesManager address on ${NETWORK}? " -r MORPHO_INTEREST_RATES_MANAGER_ADDRESS
    read -p "           ${NETWORK}'s cETH address? " -r CETH_ADDRESS
    read -p "           ${NETWORK}'s wETH address? " -r WETH_ADDRESS

	echo "Initializing Morpho-${PROTOCOL}'s Proxy on ${NETWORK} at ${MORPHO_PROXY_ADDRESS}, owned by ${DEPLOYER_ADDRESS}..."

    MAX_GAS_FOR_MATCHING=$(cast abi-encode "tuple(uint64,uint64,uint64,uint64)" 100000 100000 100000 100000)
	cast send --private-key "${DEPLOYER_PRIVATE_KEY}" "${MORPHO_PROXY_ADDRESS}" \
        0x34544040000000000000000000000000"${MORPHO_PROXY_ADDRESS:2}"000000000000000000000000"${MORPHO_POSITIONS_MANAGER_ADDRESS:2}"000000000000000000000000"${MORPHO_INTEREST_RATES_MANAGER_ADDRESS:2}""${MAX_GAS_FOR_MATCHING:2}"00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000010000000000000000000000000"${CETH_ADDRESS:2}"000000000000000000000000"${WETH_ADDRESS:2}"
fi


echo "---"
read -p "Deploy Morpho-${PROTOCOL}'s RewardsManager on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
    read -p "       Morpho-${PROTOCOL}'s Proxy address on ${NETWORK}? " -r MORPHO_PROXY_ADDRESS

	echo "Deploying Morpho-${PROTOCOL}'s RewardsManager for Proxy at ${MORPHO_PROXY_ADDRESS} on $NETWORK..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" --optimize contracts/"${PROTOCOL}"/RewardsManager.sol:RewardsManager --constructor-args "${MORPHO_PROXY_ADDRESS}"
fi
