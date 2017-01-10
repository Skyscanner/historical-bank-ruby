#!/bin/bash

# start redis server without persistence on $REDIS_PORT (if not set, start on 6390)
redis-server --save "" --appendonly no --port ${REDIS_PORT:-6390}
