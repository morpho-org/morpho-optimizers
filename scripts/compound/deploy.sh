#!/bin/bash
set -euo pipefail # exit on error
export $(xargs < .env.local)


read -p "🚀❓ Deploy Morpho-Compound's InterestRatesManager on ${NETWORK}? " -n 1 -r
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
read -p "🚀❓ Deploy Morpho-Compound's PositionsManager on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
	echo "Deploying Morpho-Compound's PositionsManager on ${NETWORK}..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" \
        --contracts contracts/compound \
        --optimize contracts/compound/PositionsManager.sol:PositionsManager \
        --verify

    echo "🎉 PositionsManager deployed!"
fi


echo "---"
read -p "🚀❓ Deploy Morpho-Compound's RewardsManager Implementation on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
	echo "Deploying Morpho-Compound's RewardsManager Implementation on ${NETWORK}..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" \
        --contracts contracts/compound \
        --optimize contracts/compound/RewardsManager.sol:RewardsManager \
        --verify

    echo "🎉 RewardsManager Implementation deployed!"
fi


echo "---"
read -p "🚀❓ Deploy Morpho-Compound's Implementation on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
	echo "Deploying Morpho-Compound's Implementation on ${NETWORK}..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" \
        --contracts contracts/compound \
        --optimize contracts/compound/Morpho.sol:Morpho \
        --verify

    echo "🎉 Morpho Implementation deployed!"
fi


echo "---"
read -p "🚀❓ Deploy Morpho-Compound's Lens Implementation on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
	echo "Deploying Morpho-Compound's Lens Implementation on $NETWORK..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" \
        --contracts contracts/compound \
        --optimize contracts/compound/Lens.sol:Lens \
        --verify

    echo "🎉 Lens Implementation deployed!"
fi


echo "---"
read -p "🚀❓ Deploy Morpho-Compound's ProxyAdmin on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
	echo "Deploying Morpho-Compound's ProxyAdmin on ${NETWORK}..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" \
        --contracts node_modules/@openzeppelin/contracts/proxy \
        --optimize node_modules/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin \
        --verify

    echo "🎉 ProxyAdmin deployed!"
fi


echo "---"
read -p "🚀❓ Deploy Morpho-Compound's Proxy on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
    read -p "       Morpho-Compound's Implementation address? " -r MORPHO_IMPL_ADDRESS
    read -p "       Morpho-Compound's ProxyAdmin address on ${NETWORK}? " -r MORPHO_PROXY_ADMIN_ADDRESS

	echo "Deploying Morpho-Compound's Proxy on ${NETWORK} for Implementation at ${MORPHO_IMPL_ADDRESS}, owned by ${MORPHO_PROXY_ADMIN_ADDRESS}..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" \
        --contracts node_modules/@openzeppelin/contracts/proxy \
        --optimize node_modules/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy \
        --verify \
        --constructor-args "${MORPHO_IMPL_ADDRESS}" "${MORPHO_PROXY_ADMIN_ADDRESS}" ""

    echo "🎉 Morpho Proxy deployed!"
fi


echo "---"
read -p "🚀❓ Deploy Morpho-Compound's RewardsManager Proxy on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
    read -p "       Morpho-Compound's RewardsManager Implementation address? " -r MORPHO_REWARDS_MANAGER_IMPL_ADDRESS
    read -p "       Morpho-Compound's ProxyAdmin address on ${NETWORK}? " -r MORPHO_PROXY_ADMIN_ADDRESS

	echo "Deploying Morpho-Compound's RewardsManager Proxy on ${NETWORK} for Implementation at ${MORPHO_REWARDS_MANAGER_IMPL_ADDRESS}, owned by ${MORPHO_PROXY_ADMIN_ADDRESS}..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" \
        --contracts node_modules/@openzeppelin/contracts/proxy \
        --optimize node_modules/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy \
        --verify \
        --constructor-args "${MORPHO_REWARDS_MANAGER_IMPL_ADDRESS}" "${MORPHO_PROXY_ADMIN_ADDRESS}" ""

    echo "🎉 RewardsManager Proxy deployed!"
fi


echo "---"
read -p "🚀❓ Deploy Morpho-Compound's Lens Proxy on ${NETWORK}? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]
then
    read -p "       Morpho-Compound's Lens Implementation address? " -r MORPHO_LENS_IMPL_ADDRESS
    read -p "       Morpho-Compound's ProxyAdmin address on ${NETWORK}? " -r MORPHO_PROXY_ADMIN_ADDRESS

	echo "Deploying Morpho-Compound's Lens Proxy on ${NETWORK} for Implementation at ${MORPHO_LENS_IMPL_ADDRESS}, owned by ${MORPHO_PROXY_ADMIN_ADDRESS}..."

	forge create --private-key "${DEPLOYER_PRIVATE_KEY}" \
        --contracts node_modules/@openzeppelin/contracts/proxy \
        --optimize node_modules/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy \
        --verify \
        --constructor-args "${MORPHO_LENS_IMPL_ADDRESS}" "${MORPHO_PROXY_ADMIN_ADDRESS}" ""

    echo "🎉 Lens Proxy deployed!"
fi


echo "---"
echo "🎉 Deployment completed!"
