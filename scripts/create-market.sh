#!/bin/bash

read -p "Morpho-${PROTOCOL}'s Proxy address on ${NETWORK}? " -r MORPHO_PROXY_ADDRESS
read -p "${PROTOCOL}'s pool token address on ${NETWORK}? " -r POOL_TOKEN_ADDRESS
read -p "Morpho-${PROTOCOL}'s reserveFactor for market ${POOL_TOKEN_ADDRESS} on ${NETWORK}? " -r RESERVE_FACTOR
read -p "Morpho-${PROTOCOL}'s p2pIndexCursor for market ${POOL_TOKEN_ADDRESS} on ${NETWORK}? " -r P2P_INDEX_CURSOR

echo "Creating market ${POOL_TOKEN_ADDRESS} via Morpho-${PROTOCOL}'s Proxy on ${NETWORK} at ${MORPHO_PROXY_ADDRESS}, with ${RESERVE_FACTOR} bps reserveFactor & ${P2P_INDEX_CURSOR} bps p2pIndexCursor..."

POOL_TOKEN_ADDRESS=$(cast abi-encode "tuple(address)" "${POOL_TOKEN_ADDRESS}")
RESERVE_FACTOR_P2P_INDEX_CURSOR=$(cast abi-encode "tuple(uint16,uint16)" "${RESERVE_FACTOR}" "${P2P_INDEX_CURSOR}")

cast send --private-key "${DEPLOYER_PRIVATE_KEY}" \
    "${MORPHO_PROXY_ADDRESS}" \
    0x7a663121"${POOL_TOKEN_ADDRESS:2}""${RESERVE_FACTOR_P2P_INDEX_CURSOR:2}"


echo "---"
echo "🎉 Market created!"
