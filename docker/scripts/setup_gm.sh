#!/bin/bash
set -eux

# User balance of stake tokens 
USER_COINS="100000000000stake"
# Amount of stake tokens staked
STAKE="100000000stake"
# Node IP address
NODE_IP="127.0.0.1"

# Home directory
HOME_DIR="/root/.gm"

HERMES_DIR="/root/.hermes"

GM_BINARY="/root/gm/bin/gm"

USERNAME="coordinator"

PROVIDER_PORT="28200"

CONSUMER_PORT="28100"

pkill -f interchain-security-pd &> /dev/null || true

rm -rf .gm

mkdir .gm

tee .gm/gm.toml<<EOF
[global]
  add_to_hermes = true
  auto_maintain_config = true
  extra_wallets = 2
  gaiad_binary = "/usr/local/bin/interchain-security-pd"
  hdpath = ""
  home_dir = "/root/.gm"
  ports_start_at = 28000
  validator_mnemonic = ""
  wallet_mnemonic = ""

  [global.hermes]
    binary = "/usr/local/bin/hermes"
    config = "/root/.hermes/config.toml"
    log_level = "info"
    telemetry_enabled = false
    telemetry_host = "127.0.0.1"
    telemetry_port = 3001

[provider]
  ports_start_at = $PROVIDER_PORT

[node2]
  network = "provider"
EOF

# Build genesis file and node directory structure
interchain-security-pd init --chain-id provider $USERNAME --home ${HOME_DIR}/provider

jq ".app_state.gov.voting_params.voting_period = \"3s\"" \
   ${HOME_DIR}/provider/config/genesis.json > \
   ${HOME_DIR}/provider/edited_genesis.json && mv ${HOME_DIR}/provider/edited_genesis.json ${HOME_DIR}/provider/config/genesis.json
sleep 1

# Create account keypair
interchain-security-pd keys add $USERNAME --home ${HOME_DIR}/provider --keyring-backend test --output json > ${HOME_DIR}/provider/${USERNAME}_prov_keypair.json 2>&1
sleep 1

# Add stake to user
interchain-security-pd add-genesis-account $(jq -r .address ${HOME_DIR}/provider/${USERNAME}_prov_keypair.json) $USER_COINS --home ${HOME_DIR}/provider --keyring-backend test
sleep 1

# Stake 1/1000 user's coins
interchain-security-pd gentx $USERNAME $STAKE --chain-id provider --home ${HOME_DIR}/provider --keyring-backend test --moniker $USERNAME
sleep 1

interchain-security-pd collect-gentxs --home ${HOME_DIR}/provider --gentx-dir ${HOME_DIR}/provider/config/gentx/
sleep 1

sed -i -r "/node =/ s/= .*/= \"tcp:\/\/${NODE_IP}:${PROVIDER_PORT}\"/" ${HOME_DIR}/provider/config/client.toml
sed -i -r 's/timeout_commit = "5s"/timeout_commit = "3s"/g' ${HOME_DIR}/provider/config/config.toml
sed -i -r 's/timeout_propose = "3s"/timeout_propose = "1s"/g' ${HOME_DIR}/provider/config/config.toml

$GM_BINARY start
# Build consumer chain proposal file
tee ${HOME_DIR}/consumer-proposal.json<<EOF
{
    "title": "Create a chain",
    "description": "Gonna be a great chain",
    "chain_id": "consumer",
    "initial_height": {
        "revision_height": 1
    },
    "genesis_hash": "Z2VuX2hhc2g=",
    "binary_hash": "YmluX2hhc2g=",
    "spawn_time": "2022-03-11T09:02:14.718477-08:00",
    "deposit": "10000001stake"
}
EOF

interchain-security-pd keys show $USERNAME --keyring-backend test --home ${HOME_DIR}/provider

# Submit consumer chain proposal
interchain-security-pd tx gov submit-proposal consumer-addition ${HOME_DIR}/consumer-proposal.json --chain-id provider --from $USERNAME --home ${HOME_DIR}/provider --node tcp://${NODE_IP}:${PROVIDER_PORT}  --keyring-backend test -b block -y

sleep 1

# Vote yes to proposal
interchain-security-pd tx gov vote 1 yes --from $USERNAME --chain-id provider --home ${HOME_DIR}/provider -b block -y --keyring-backend test
sleep 5

# Clean start
pkill -f interchain-security-cd &> /dev/null || true
rm -rf ${HOME_DIR}/consumer

# Build genesis file and node directory structure
interchain-security-cd init --chain-id consumer $USERNAME --home ${HOME_DIR}/consumer
sleep 1

# Create user account keypair
interchain-security-cd keys add $USERNAME --home ${HOME_DIR}/consumer --keyring-backend test --output json > ${HOME_DIR}/consumer/${USERNAME}_cons_keypair.json 2>&1

# Add stake to user account
interchain-security-cd add-genesis-account $(jq -r .address ${HOME_DIR}/consumer/${USERNAME}_cons_keypair.json)  1000000000stake --home ${HOME_DIR}/consumer

# Add consumer genesis states to genesis file
interchain-security-pd query provider consumer-genesis consumer --home ${HOME_DIR}/provider -o json > ${HOME_DIR}/consumer_gen.json
jq -s '.[0].app_state.ccvconsumer = .[1] | .[0]' ${HOME_DIR}/consumer/config/genesis.json ${HOME_DIR}/consumer_gen.json > ${HOME_DIR}/consumer/edited_genesis.json && mv ${HOME_DIR}/consumer/edited_genesis.json ${HOME_DIR}/consumer/config/genesis.json
rm ${HOME_DIR}/consumer_gen.json

jq ".app_state.gov.voting_params.voting_period = \"3s\" | .app_state.staking.params.unbonding_time = \"600s\"" \
	   ${HOME_DIR}/consumer/config/genesis.json > \
	   ${HOME_DIR}/consumer/edited_genesis.json && mv ${HOME_DIR}/consumer/edited_genesis.json ${HOME_DIR}/consumer/config/genesis.json

# Create validator states
echo '{"height": "0","round": 0,"step": 0}' > ${HOME_DIR}/consumer/data/priv_validator_state.json

# Copy validator key files
cp ${HOME_DIR}/provider/config/priv_validator_key.json ${HOME_DIR}/consumer/config/priv_validator_key.json
cp ${HOME_DIR}/provider/config/node_key.json ${HOME_DIR}/consumer/config/node_key.json

# Set default client port
sed -i -r "/node =/ s/= .*/= \"tcp:\/\/${NODE_IP}:${CONSUMER_PORT}\"/" ${HOME_DIR}/consumer/config/client.toml

# Start giaia
interchain-security-cd start --home ${HOME_DIR}/consumer \
        --rpc.laddr tcp://${NODE_IP}:${CONSUMER_PORT} \
        --grpc.address ${NODE_IP}:9081 \
        --address tcp://${NODE_IP}:26645 \
        --p2p.laddr tcp://${NODE_IP}:26646 \
        --grpc-web.enable=false \
        &> ${HOME_DIR}/consumer/logs &

sleep 3

mkdir ${HERMES_DIR}
tee ${HERMES_DIR}/config.toml<<EOF
[global]
log_level = "info"

[mode]

[mode.clients]
enabled = true
refresh = true
misbehaviour = true

[mode.connections]
enabled = false

[mode.channels]
enabled = false

[mode.packets]
enabled = true

[[chains]]
account_prefix = "cosmos"
clock_drift = "5s"
gas_multiplier = 1.1
grpc_addr = "tcp://${NODE_IP}:9081"
id = "consumer"
key_name = "relayer"
max_gas = 2000000
rpc_addr = "http://${NODE_IP}:${CONSUMER_PORT}"
rpc_timeout = "10s"
store_prefix = "ibc"
trusting_period = "3minutes"
websocket_addr = "ws://${NODE_IP}:${CONSUMER_PORT}/websocket"

[chains.gas_price]
       denom = "stake"
       price = 0.00

[chains.trust_threshold]
       denominator = "3"
       numerator = "1"

[[chains]]
account_prefix = "cosmos"
clock_drift = "5s"
gas_multiplier = 1.1
grpc_addr = "tcp://${NODE_IP}:28202"
id = "provider"
key_name = "relayer"
max_gas = 2000000
rpc_addr = "http://${NODE_IP}:${PROVIDER_PORT}"
rpc_timeout = "10s"
store_prefix = "ibc"
trusting_period = "3minutes"
websocket_addr = "ws://${NODE_IP}:${PROVIDER_PORT}/websocket"

[chains.gas_price]
       denom = "stake"
       price = 0.00

[chains.trust_threshold]
       denominator = "3"
       numerator = "1"
EOF

# Delete all previous keys in relayer
hermes keys delete --chain consumer --all
hermes keys delete --chain provider --all

echo $(jq -r .mnemonic ${HOME_DIR}/consumer/${USERNAME}_cons_keypair.json) > ${HOME_DIR}/key_cons_mnemonics
echo $(jq -r .mnemonic ${HOME_DIR}/provider/${USERNAME}_prov_keypair.json) > ${HOME_DIR}/key_prov_mnemonics

# Restore keys to hermes relayer
hermes keys add --mnemonic-file ${HOME_DIR}/key_cons_mnemonics --chain consumer
hermes keys add --mnemonic-file ${HOME_DIR}/key_prov_mnemonics --chain provider

sleep 5

$GM_BINARY status

hermes create connection --a-chain consumer \
    --a-client 07-tendermint-0 \
    --b-client 07-tendermint-0

hermes create channel --a-chain consumer \
    --a-port consumer \
    --b-port provider \
    --order ordered \
    --channel-version 1 --a-connection connection-0

sleep 5

hermes --json start &> ~/.hermes/logs &

interchain-security-pd q tendermint-validator-set --home ${HOME_DIR}/provider
interchain-security-cd q tendermint-validator-set --home ${HOME_DIR}/consumer

DELEGATIONS=$(interchain-security-pd q staking delegations \
	$(jq -r .address ${HOME_DIR}/provider/${USERNAME}_prov_keypair.json) \
	--home ${HOME_DIR}/provider -o json)

OPERATOR_ADDR=$(echo $DELEGATIONS | jq -r '.delegation_responses[0].delegation.validator_address')

interchain-security-pd tx staking delegate $OPERATOR_ADDR 1000000stake \
       	--from $USERNAME \
       	--keyring-backend test \
       	--home ${HOME_DIR}/provider \
       	--chain-id provider \
	    -y -b block

sleep 13

interchain-security-pd q tendermint-validator-set --home ${HOME_DIR}/provider
interchain-security-cd q tendermint-validator-set --home ${HOME_DIR}/consumer
