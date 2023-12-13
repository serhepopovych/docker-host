#!/bin/sh

docker network rm 'macvlan1' ||:
docker network create --driver='macvlan' \
    --subnet='10.1.1.0/24' \
    --gateway='10.1.1.1' \
    -o 'macvlan_mode=bridge' \
    -o 'parent=en0' \
    'macvlan1' \
    #
