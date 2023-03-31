#!/bin/bash
set -eux

HOME_DIR="/root/.gm"

USERNAME="coordinator"

GM_BINARY="/root/gm/bin/gm"

$GM_BINARY stop provider

interchain-security-pd export --home ${HOME_DIR}/provider --log_format=json > provider-genesis-exp.json 2>&1

cp provider-genesis-exp.json ${HOME_DIR}/provider/config/genesis.json

rm provider-genesis-exp.json

cp -r ${HOME_DIR}/provider/data ${HOME_DIR}/provider/provider-data.bak

interchain-security-pd unsafe-reset-all --home ${HOME_DIR}/provider

$GM_BINARY start provider