#!/bin/bash

HOST="90.90.97.27"
PORT_PROXY="8080"
PORT_P="13900"
PORT_D="13901"

python load_balance_proxy_server_example.py \
    --host ${HOST} \
    --port ${PORT_PROXY} \
    --prefiller-hosts ${HOST} \
    --prefiller-port ${PORT_P} \
    --decoder-hosts ${HOST} \
    --decoder-ports 1${PORT_D}
