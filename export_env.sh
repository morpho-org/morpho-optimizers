#!/bin/sh

[ -z "${PROTOCOL}" ] && export PROTOCOL="compound"
[ -z "${NETWORK}" ] && export NETWORK="eth-mainnet"

[ -z "${FOUNDRY_SRC}" ] && export FOUNDRY_SRC="src/${PROTOCOL}/"

[ -z "${FOUNDRY_PROFILE}" ] && export FOUNDRY_PROFILE="${PROTOCOL}"
[ -z "${FOUNDRY_REMAPPINGS}" ] && export FOUNDRY_REMAPPINGS="@config/=config/${NETWORK}/${PROTOCOL}/"
[ -z "${FOUNDRY_PRIVATE_KEY}" ] && export FOUNDRY_PRIVATE_KEY="${DEPLOYER_PRIVATE_KEY}"

if [ "${FOUNDRY_PROFILE}" = "production" ]; then
    export FOUNDRY_TEST="test/prod/${PROTOCOL}/"
else
    export FOUNDRY_TEST="test/${PROTOCOL}/"
fi
