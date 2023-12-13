#!/bin/sh -e

PM2_INITIALIZED='/etc/ssh/hostkeys/ssh_host_rsa_key'
if [ ! -e "$PM2_INITIALIZED" ]; then
    t="${PM2_INITIALIZED%/*}"
    install -d "$t/${t%/*}"
    ssh-keygen -A -f "$t"
fi

exec pm2-runtime start ecosystem.config.js
