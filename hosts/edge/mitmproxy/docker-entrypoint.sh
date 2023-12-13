#!/bin/sh

# Rquires: stat(1), usermod(1), gosu(1)

set -e
set -u
#set -x

readonly \
    mitmproxy_user='@user@' \
    mitmproxy_home=~@user@ \
    #

for t in \
    '.mitmproxy/mitmproxy-ca.pem' \
    '' \
    #
do
    if t="$mitmproxy_home/$t" && [ -e "$t" ]; then
        usermod 2>/dev/null -o \
            -u $(stat -c "%u" "$t") \
            -g $(stat -c "%g" "$t") \
            "$mitmproxy_user" \
            #
        break
    fi
done

cmd="${1:-mitmweb}"
[ -n "${1+x}" ] && shift

case "$cmd" in
    'mitmdump'|'mitmproxy'|'mitmweb')
        exec gosu "$mitmproxy_user" "$cmd" "$@"
        ;;
    *)
        exec "$cmd" "$@"
        ;;
esac
