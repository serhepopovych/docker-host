#!/bin/sh -e

PM2_INITIALIZED='./ecosystem.config.js.templ'
if [ -e "$PM2_INITIALIZED" ]; then
    app_dir='@app_dir@'
    cron_minute=$(($(od -vAn -N1 -tu1 /dev/urandom) % 60))

    sed -e "s,%app_dir%,$app_dir,g" \
        -e "s,%cron_minute%,$cron_minute,g" \
         "$PM2_INITIALIZED" >"${PM2_INITIALIZED%.templ}"

    rm -f "$PM2_INITIALIZED"
fi

exec pm2-runtime start ecosystem.config.js
