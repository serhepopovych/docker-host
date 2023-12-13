#!/bin/sh -e

readonly \
    ngx_cache='/var/cache/nginx/' \
    ngx_dhparam='dh2048.pem' \
    #

PM2_INITIALIZED='./ecosystem.config.js.templ'
if [ -e "$PM2_INITIALIZED" ]; then
    # nginx
    t="$ngx_cache$ngx_dhparam"
    [ -s "$t" ] || openssl dhparam -out "$t" 2048

    # cron
    cbt_cron_minute=$(($(od -vAn -N1 -tu1 /dev/urandom) % 60))

    sed -e "s,%cbt_cron_minute%,$cbt_cron_minute,g" \
         "$PM2_INITIALIZED" >"${PM2_INITIALIZED%.templ}"

    rm -f "$PM2_INITIALIZED"
else
    # remove stale files
    find "$ngx_cache" ! -name "$ngx_dhparam" -a ! -type d -a -delete
fi

exec pm2-runtime start ecosystem.config.js
