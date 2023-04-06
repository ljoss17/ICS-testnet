## Prerequisite

Add the desired Hermes version in the `docker/` folder

## Instructions

### Build Docker image
`docker build --tag is-testnet .`

### Start Docker container
`make with-gm-testnet`

### Restart provider
`make restart-provider`

### Delegate
`make delegate`

### Verify Hermes logs
`make relayer-logs`

### Call update client CLI

From the relayer logs retrieve the restart height. This can be taken from the error message:

```
"ERROR","fields":{"message":"will retry: schedule execution encountered error: failed during a client operation: error raised while updating client on chain consumer: failed building header with error: light client error for RPC address provider: rpc error: response error: Internal error: height 37 is not available, lowest height is 52 (code: -32603)"}
```

Or run the client update command without the new optional flags: `docker exec $(docker ps -q) hermes update client --host-chain consumer --client 07-tendermint-0`, which should result in:

```
ERROR foreign client error: error raised while updating client on chain consumer: failed building header with error: light client error for RPC address provider: rpc error: response error: Internal error: height 37 is not available, lowest height is 52 (code: -32603)
```

In this case the restart height is `52`.

Manually update the client using the command: `docker exec $(docker ps -q) hermes update client --host-chain consumer --client 07-tendermint-0 --archive-address http://127.0.0.1:28000 --restart-height 52 --height 53`

This command updates the client to height `53` which will allow the client to update itself without using a separate node.

It should now be possible to update the client to the latest height by calling: `docker exec $(docker ps -q) hermes update client --host-chain consumer --client 07-tendermint-0`