#!/bin/sh -e

export GUACAMOLE_HOME='/tmp/.guacamole.template'

# Start with a fresh GUACAMOLE_HOME. See /opt/guacamole/bin/start.sh
# for GUACAMOLE_HOME_TEMPLATE and GUACAMOLE_HOME usage.

rm -Rf "$GUACAMOLE_HOME" ||:
install -d "$GUACAMOLE_HOME" ||:

# Usage: guacamole_ldap_servers_yml
guacamole_ldap_servers_yml()
{
    local ldap_hostname="${LDAP_HOSTNAME-}"
    [ -n "$ldap_hostname" ] || return 0

    getent ahosts "$ldap_hostname" | {
        # Make network-timeout and operation-timeout given in seconds time unit
        ldap_network_timeout=$((@ldap_network_timeout@ * 1000))
        ldap_ips=' '
        while read -r ip _; do
            if [ -n "${ldap_ips##* \'$ip\' *}" ]; then
                ldap_ips="$ldap_ips'$ip' "
            fi
        done

        eval set -- $ldap_ips

        if [ $# -gt 1 ]; then
            printf > "$GUACAMOLE_HOME/ldap-servers.yml" -- \
                '- hostname: %s\n' "$@" \
                #
            printf > "$GUACAMOLE_HOME/guacamole.properties" -- \
                'ldap-network-timeout: %s\n' $ldap_network_timeout \
                #
        fi
    }
}
guacamole_ldap_servers_yml

exec "$@"
