#!/bin/sh

# Requires: cat(1), sed(1), docker(1), jq(1)

# Application
app='guacamole'

# Network
network='nft-isolated'
ip='192.0.2.222'
ip_guacd='192.0.2.221'

################################################################################

# Set option(s)
set -e
set -u

## Enable debug/trace
#exec 2>"/tmp/${0##*/}.debug.$(date '+%s.%N')"
#set >&2
#set -x

this_prog='libdeploy.sh'

if [ ! -e "$0" -o "$0" -ef "/proc/$$/exe" ]; then
    # Executed script is
    #  a) read from stdin through pipe
    #  b) specified via -c option
    #  d) sourced
    this="$this_prog"
    this_dir='./'
else
    # Executed script exists and it's inode differs
    # from process exe symlink (Linux specific)
    this="$0"
    this_dir="${this%/*}/"
fi
this_dir="$(cd "$this_dir" && echo "$PWD")"

################################################################################

# Helpers
. "$this_dir/libdeploy/sh"

readonly \
    gua_volume_name="guac-guacd${inst:+_$inst}.rdpdr" \
    gua_volume_path='/home/guacd/X' \
    #

# Usage: parse_args_usage
parse_args_usage()
{
    cat <<EOF
    --ip_guacd=${ip_guacd:-<dynamic>}
        IP address in network given by --network for guacd proxy. Use
        dynamic IP if empty

  for guacamole:
    --gua_db_name=$gua_db_name
        Database name to connect
    --gua_db_user=$gua_db_user
    --gua_db_pass=${gua_db_pass:-<random>}
        Username and password to authenticate as for database access

    --gua_ip_edge=$gua_ip_edge
    --gua_ip_docker=$gua_ip_docker
        Guacamole connection hostname, IP address or empty to skip
        connection creation

    --gua_api_user=$gua_api_user
    --gua_api_pass=$gua_api_pass
        Username and password to authenticate to guacamole for automated
        management (e.g. connection, user and group creation) from this
        and other projects ci/$this_prog script

    --gua_volume_opts=$gua_volume_opts
        Docker volume driver specific options (e.g. size=10G for local driver)
EOF
}

# Usage: parse_args_pre ...
parse_args_pre()
{
    # read profile
    eval "local ${app}_name"
    eval "local ${app}_image"
    eval "local ${app}_network"

    eval "local ${app}_ip_guacd"

    eval "local ${app}_ip_edge"
    eval "local ${app}_ip_docker"

    eval "local ${app}_db_name"
    eval "local ${app}_db_user"
    eval "local ${app}_db_pass"

    eval "local ${app}_api_user"
    eval "local ${app}_api_pass"

    eval "local ${app}_volume_opts"

    read_profile_guacamole \
        'name' 'image' 'network' \
        'ip_guacd' \
        'ip_edge' 'ip_docker' \
        'db_name' 'db_user' 'db_pass' \
        'volume_opts' \
        #

    # network
    eval "network=\"\${${app}_network:-\$network}\""
    eval "ip=\"\${gua_ip}\""
    eval "ip_guacd=\"\${${app}_ip_guacd:-\$ip_guacd}\""

    eval "gua_ip_edge=\"\${${app}_ip_edge-edge.local}\""
    eval "gua_ip_docker=\"\${${app}_ip_docker-docker.local}\""

    # guacamole
    eval "gua_db_name=\"\${${app}_db_name:-guacamole}\""
    eval "gua_db_user=\"\${${app}_db_user:-guacamole}\""
    eval "gua_db_pass=\"\${${app}_db_pass:-}\""

    eval "gua_api_user=\"\${${app}_api_user:-\${_gua_api_user}}\""
    eval "gua_api_pass=\"\${${app}_api_pass:-\${_gua_api_pass}}\""

    eval "gua_volume_opts=\"\${${app}_volume_opts:-size=10G}\""
}

# Usage: parse_args_post ...
parse_args_post()
{
    readonly gua_ip="$ip"
    parse_args__post "$@"
}

# Usage: parse_args_opt --<name>=[<value>]
parse_args_opt()
{
    case "$1" in
        # network
        --ip_guacd=*)
            arg "$1" 'non-empty-value'
            ;;

        # guacamole
        --gua_db_name=*|--gua_db_user=*|--gua_db_pass=*)
            arg "$1" 'non-empty-value'
            ;;

        --gua_ip_edge=*|--gua_ip_docker=*)
            arg "$1"
            ;;

        --gua_api_user=*|--gua_api_pass=*)
            arg "$1" 'non-empty-value'
            ;;

        --gua_volume_opts=*)
            arg "$1" 'non-empty-value'
            ;;

        # error
        *)
            ! :
            ;;
    esac
}

# Usage: up ...
up()
{
    local func="${FUNCNAME:-up}"

    # Parse command line arguments
    parse_args "$@"

    # read profile 'mariadb'
    local t="mariadb${inst:+_$inst}"

    eval "local ${t}_name"
    eval "local ${t}_host"
    eval "local ${t}_user"
    eval "local ${t}_pass"

    read_profile_nocommon_or_fail "$t" \
        'name' 'host' 'user' 'pass' \
        #

    eval "local mdb_name=\"\${${t}_name}\""
    eval "local mdb_host=\"\${${t}_host}\""
    eval "local mdb_user=\"\${${t}_user}\""
    eval "local mdb_pass=\"\${${t}_pass}\""

    # deps
    mysql_test_ct "$mdb_name" "$mdb_user" "$mdb_pass"
    mysql_test_db "$mdb_name" \
        --user="$mdb_user" \
        --password="$mdb_pass" \
        --database="$gua_db_name" \
    || init_data='yes'

    # read profile 'guacamole' (fake)
    if [ -n "$init_data" ]; then
        # Use default guacamole API user/pass when reinitializing data
        eval "local ${app}_api_user=\"\${_gua_api_user}\""
        eval "local ${app}_api_pass=\"\${_gua_api_pass}\""
        # Force default guacamole admin user
        local gua_api_user="${_gua_api_user}"
    else
        eval "local ${app}_api_user=\"\$gua_api_user\""
        eval "local ${app}_api_pass=\"\$gua_api_pass\""
    fi

    ## guacamole

    local name_guacamole="guac-guacamole${inst:+_$inst}"
    local image_guacamole="${_app}/guacamole:$tag"
    local name_guacd="guac-guacd${inst:+_$inst}"
    local image_guacd="${_app}/guacd:$tag"
    local name
    local image

    : ${gua_db_pass:=$(pwmake)}

    name="$name_guacamole" \
        docker_rm
    name="$name_guacd" \
        docker_rm

    image="$image_guacamole" \
        docker_pull
    image="$image_guacd" \
        docker_pull

    # Usage: mysql_init_db
    mysql_init_db()
    {
        echo -n '* Initialize MySQL (MariaDB) database...'
        if [ -n "$init_data" ]; then
            echo " $gua_db_name"
            {
                sed -e "s,@gua_db_name@,$gua_db_name,g" \
                    -e "s,@gua_db_user@,$gua_db_user,g" \
                    -e "s,@gua_db_pass@,$gua_db_pass,g" \
                    -e "s,@ip@,$ip,g" \
                    "$this_dir/../${_app}/db/init.sql"
                echo

                docker run --rm \
                    --network=none \
                    "$image_guacamole" \
                    /opt/guacamole/bin/initdb.sh --mysql
            } | {
                mysql_batch "$mdb_name" \
                    --user="$mdb_user" \
                    --password="$mdb_pass" \
                    #
            }
        else
            echo ' skipped'
        fi
    }
    mysql_init_db

    name="$name_guacamole" image="$image_guacamole" \
        docker_run "$run_args" \
            --env=MYSQL_HOSTNAME="$mdb_host" \
            --env=MYSQL_USER="$gua_db_user" \
            --env=MYSQL_PASSWORD="$gua_db_pass" \
            --env=MYSQL_DATABASE="$gua_db_name" \
            \
            --env=GUACD_HOSTNAME="$name_guacd" \
            #

    ## guacd

    image="$image_guacd" \
        docker_volume \
            "$gua_volume_name!$gua_volume_path!$gua_volume_opts!/home/guacd" \
            #

    name="$name_guacd" image="$image_guacd" ip="$ip_guacd" \
        docker_run "$run_args" \
            #

    ## guacamole configure

    # Usage: gua_cfg_cb ...
    gua_cfg_cb()
    {
        local t n c g u p
        local hostname

        set -- -o '/dev/null'

        for g in \
            'devs' \
            'ops' \
            #
        do
            # Create new or modify existing user group
            t="$gua_json_dir/$g.userGroups.json"

            gua_api <"$t" 'UPDATE' "userGroups/@$g@" "$@" || return

            # Add or modify system permissions to user group
            t="$gua_json_dir/$g.system.userGroups.permissions.json"
            [ ! -r "$t" ] ||
            gua_api <"$t" 'PATCH' "userGroups/$g/permissions" "$@" || return
        done

        for c in \
            'edge' \
            'docker' \
            #
        do
            eval "hostname=\"\${gua_ip_${c}-}\"" && [ -n "$hostname" ] &&
                t="$gua_json_dir/$c.connections.json" &&
            n="$(jq -r '.name' "$t")" && [ -n "$n" ] &&
                g='' || g='!'

            echo -n " $g$c"

            # Skip connection if hostname or name is empty
            [ -z "$g" ] || continue

            sed "$t" \
                -e "s,@root_passwd@,${root_passwd-},g" \
                -e "s,@hostname@,$hostname,g" \
            gua_api 'UPDATE' "connections/@$n@" "$@" || return

            # Find id of the connection created/modified above
            n="$(
                gua_api 'GET' 'connections' | \
                jq -r ".[]|select(.name == \"$n\")|.identifier"
            )" && [ -n "$n" ] || return

            for g in \
                'devs' \
                'ops' \
                #
            do
                # Add or modify connections
                t="$gua_json_dir/$g.$c.userGroups.permissions.json"
                [ ! -r "$t" ] ||
                sed -e "s,@connection@,$n,g" "$t" | \
                gua_api 'PATCH' "userGroups/$g/permissions" "$@" || return
            done
        done

        eval "u=\"\${${app}_api_user}\""
        eval "p=\"\${${app}_api_pass}\""

        if [ "$p" = "${_gua_api_pass}" ]; then
            t="${gua_api_pass#${_gua_api_pass}}"
            t="${t:-$(pwmake)}"
            gua_api 'PUT' "users/$u/password" "$@" <<EOF
{
  "oldPassword": "$p",
  "newPassword": "$t"
}
EOF
            eval "${app}_api_pass=\"\$t\""
        fi
    }
    guacamole_config

    # write profile
    eval "local ${app}_name=\"\$name_guacamole\""
    eval "local ${app}_image=\"\$image_guacamole\""
    eval "local ${app}_network=\"\$network\""
    eval "local ${app}_ip=\"\$ip\""

    eval "local ${app}_name_guacd=\"\$name_guacd\""
    eval "local ${app}_image_guacd=\"\$image_guacd\""
    eval "local ${app}_ip_guacd=\"\$ip_guacd\""

    eval "local ${app}_ip_edge=\"\$gua_ip_edge\""
    eval "local ${app}_ip_docker=\"\$gua_ip_docker\""

    eval "local ${app}_db_name=\"\$gua_db_name\""
    eval "local ${app}_db_user=\"\$gua_db_user\""
    eval "local ${app}_db_pass=\"\$gua_db_pass\""

    #eval "local ${app}_api_user=\"\$gua_api_user\""
    #eval "local ${app}_api_pass=\"\$gua_api_pass\""

    eval "local ${app}_volume_opts=\"\$gua_volume_opts\""

    write_profile_or_fail "$app" \
        'name_guacd' 'image_guacd' 'ip_guacd' \
        'ip_edge' 'ip_docker' \
        'db_name' 'db_user' 'db_pass' \
        'api_user' 'api_pass' \
        'volume_opts' \
        #
}

# Usage: down ...
down()
{
    local func="${FUNCNAME:-down}"

    # read profile
    eval "local ${app}_name"
    eval "local ${app}_image"
    eval "local ${app}_name_guacd"
    eval "local ${app}_image_guacd"

    eval "local ${app}_db_name"
    eval "local ${app}_db_user"

    eval "local ${app}_api_user"
    eval "local ${app}_api_pass"

    read_profile_guacamole \
        'name' 'image' \
        'name_guacd' 'image_guacd' \
        'db_name' 'db_user' \
        #

    eval "local name_guacamole=\"\${${app}_name}\""
    eval "local image_guacamole=\"\${${app}_image}\""
    eval "local name_guacd=\"\${${app}_name_guacd}\""
    eval "local image_guacd=\"\${${app}_image_guacd}\""

    eval "local gua_db_name=\"\${${app}_db_name}\""
    eval "local gua_db_user=\"\${${app}_db_user}\""

    # read profile 'mariadb'
    local t="mariadb${inst:+_$inst}"

    eval "local ${t}_name"
    eval "local ${t}_user"
    eval "local ${t}_pass"

    read_profile_nocommon_or_bail "$t" \
        'name' 'user' 'pass' \
        #

    eval "local mdb_name=\"\${${t}_name-}\""
    eval "local mdb_user=\"\${${t}_user-}\""
    eval "local mdb_pass=\"\${${t}_pass-}\""

    ## guacamole

    local name
    local image

    name="$name_guacamole" \
        docker_rm
    name="$name_guacd" \
        docker_rm

    ## guacd

    image="$image_guacd" \
        docker_volume_rm \
            "$gua_volume_name" \
            #

    # Usage: mysql_fini_db
    mysql_fini_db()
    {
        echo -n '* Finalize MySQL (MariaDB) database...'
        if [ -n "$mdb_pass" ]; then
            echo " $gua_db_name"
            {
                sed -n \
                    -e '/^DROP\s\+/!b' \
                    -e "s,@gua_db_name@,$gua_db_name,g" \
                    -e "s,@gua_db_user@,$gua_db_user,g" \
                    -e "s,@ip@,$gua_ip,g" \
                    -e 'p' \
                    "$this_dir/../${_app}/db/init.sql"
                echo
            } | {
                mysql_batch "$mdb_name" \
                    --user="$mdb_user" \
                    --password="$mdb_pass" \
                    #
            }
        else
           echo ' skipped'
        fi
    }
    mysql_fini_db

    ## Sanitize profile
    sysprep_profile "$app"
}

# See how we've called
case "$prog_name" in
    'up.sh')
        up "$@"
        ;;
    'down.sh')
        down "$@"
        ;;
    *)
        fatal '%s: Must be called as "%s" or "%s", but alled as "%s"\n' \
            "$this_prog" 'up.sh' 'down.sh' "$prog_name" \
            #
        ;;
esac
