#!/bin/sh

# Requires: install(1), head(1), sed(1), find(1), hostname(1), id(1),
#           openssl(1), docker(1), mysql(1), curl(1), jq(1)

[ -z "${__libdeploy_sh__-}" ] || return 0
__libdeploy_sh__=1

## Global helpers and steps

true()  {   :; }
false() { ! :; }

# Usage: is_yes ...
is_yes()
{
    case "${1-}" in
        [Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|[Oo][Nn]|1)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Usage: is_no ...
is_no()
{
    case "${1-}" in
        [Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]|[Oo][Ff][Ff]|0)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Usage: msg <fmt> ...
msg()
{
    local rc=$?

    local func="${FUNCNAME:-msg}"

    local fmt="${1:?missing 1st arg to ${func}() (<fmt>)}"
    shift

    [ $V -le 0 ] || printf -- "$fmt" "$@"

    return $rc
}

# Usage: info <fmt> ...
info()
{
    msg "$@"
}

# Usage: error <fmt> ...
error()
{
    msg "$@" >&2
}

# Usage: fatal <fmt> ...
fatal()
{
    local rc=$?
    printf >&2 -- '%s: ' "$prog_name"
    error "$@"
    exit $rc
}

# Usage: abort <fmt> ...
abort()
{
    local rc=$?
    trap - EXIT
    V=1 error "$@"
    exit $rc
}

# Usage: _exit [<rc>]
_exit()
{
    local _rc=$?
    trap - EXIT
    local rc="${1:-${_rc}}"
    [ "$rc" -ge 0 -o "$rc" -lt 0 ] 2>/dev/null || rc=${_rc}
    exit $rc
}

# Usage: safe_curl <url> <size> [<curl(1) options>...]
safe_curl()
{
    local func="${FUNCNAME:-safe_curl}"

    local url="${1:?missing 1st arg to ${func}() <url>}" && shift
    local size="${1:?missing 2d arg to ${func}() <size>}" && shift

    [ "$size" -gt 0 ] 2>/dev/null

    exec 4>&1
    eval $(
        exec 3>&1
        {
            set +e
            curl "$@" -s "$url"
            echo >&3 "local rc=$?"
        } | head -c $size >&4
    )
    exec 4>&-

    return $rc
}

# Usage: pwmake [<length>] [<f_pw_ambiguous>]
pwmake()
{
    # From pwgen/pw_rand.c
    local pw_ambiguous='B8G6I1l0OQDS5Z2'

    eval "
        tr -dc '0-9a-zA-Z' </dev/urandom 2>/dev/null |
        ${2:+tr -d "$pw_ambiguous" 2>/dev/null |}
        head -c '${1:-16}'
    "
    echo
}

# Usage: crypt <pass> [-{1|apr1|5|6}]
crypt()
{
    local func="${FUNCNAME:-crypt}"

    local pass="${1:?missing 1st arg to ${func}() <pass>}"

    # use sha256 for hash (option -5) by default
    local hash="${2:--5}"
    case "$hash" in
        -1|-apr1|-5|-6)
            printf '%s\n' "$pass" | \
            openssl passwd "$hash" -stdin -salt "$(pwmake)"
            ;;
        *)
            hash=''
            : ${hash:?\$hash is not valid}
            ;;
    esac
}

# Usage: parse_args_init
parse_args_init()
{
    # Usage: parse_args_usage
    parse_args_usage()
    {
        :
    }
    # Usage: parse_args_pre ...
    parse_args_pre()
    {
        :
    }
    # Usage: parse_args_opt --<name>=[<value>]
    parse_args_opt()
    {
        ! :
    }
    # Usage: parse_args_post ...
    parse_args__post()
    {
        [ $# -le 0 ] || usage

        tag="${tag##*:}" && tag="${tag:-latest}"
    }
    parse_args_post()
    {
        parse_args__post "$@"
    }
}
parse_args_init

# Usage: parse_args ...
parse_args()
{
    local func="${FUNCNAME:-parse_args}"

    # Usage: usage
    usage()
    {
        local rc=$?
        local fd

        [ $rc -eq 0 ] && fd=1 || fd=2

        cat >&$fd <<EOF
Usage: $prog_name [options] \\
  [-- [<docker-build(1)-options>] [-- [<docker-run(1)-options>]]] [-- arguments]

Options and their defaults:
    --tag=$tag
        Image tag (e.g. latest). Use default tag if empty.

    --no_update
        Do not pull, possibly updated, image from registry before docker-run(1)
        or rebuild, in case of local, image with docker-build(1) unless it
        does not exist.
    --init_data
        (Re)initialize container associated data such as docker volumes,
        database(s) on server etc.

    --network=${network:-<default>}
        Docker network to attach container to. Use default network if empty.
    --ip=${ip:-<dynamic>}
        IP address in network given by --network. Use dynamic IP if empty.
$(parse_args_usage)

  common:
    --help, --usage
        This help/usage message
    --version
        This program version
EOF
        exit $rc
    }
    # Usage: arg --<name>=[<value>] [<non-empty-value>]
    arg()
    {
        [ $# -ge 1 -a -n "${1-}" ] || usage

        local t="${1##--}"
        [ "$t" != "$1" ] || usage
        local n="${t%%=*}"
        [ "$n" != "$t" -a -n "$n" ] || usage

        local v="${1#--$n=}"
        [ "$v" != "$1" ] || usage
        [ -z "${2-}" ] || [ -n "$v" ] || usage

        eval "$n='$v'" || usage
    }
    # Usage: opt --<name>=[<value>]
    opt()
    {
        if parse_args_opt "$1"; then
            :
        else
            local rc=$?
            printf >&2 -- '%s: unknown option: %s\n' "$prog_name" "${1%%=*}"
            exit $rc
        fi
    }

    # pre
    : ${tag:='latest'} ${network:=''} ${ip:=''}

    no_update=''
    init_data=''

    parse_args_pre "$@"

    # docker-build(1)
    unset build_args
    # docker-run(1)
    unset run_args

    while [ $# -gt 0 ]; do
        case "$1" in
            --)
                  if [ -n "${run_args+x}" ]; then
                    break
                elif [ -n "${build_args+x}" ]; then
                    run_args=''
                else
                    build_args=''
                fi
                shift && continue
                ;;
            *)
                  if [ -n "${run_args+x}" ]; then
                    run_args="$run_args'$1' "
                    shift && continue
                elif [ -n "${build_args+x}" ]; then
                    build_args="$build_args'$1' "
                    shift && continue
                fi
                ;;
        esac

        case "$1" in
            # tag
            --tag=*)
                arg "$1"
                ;;
            --tag)
                arg "$1=${2-}"
                ${2+shift}
                ;;

            # network/ip
            --network=*|--ip=*)
                arg "$1"
                ;;
            --network|--ip)
                arg "$1=${2+$2}"
                ${2+shift}
                ;;

            # update & init
            --no_update|--init_data)
                arg "$1=yes"
                ;;

            # common
            --help|--usage)
                usage
                ;;
            --version)
                echo "$prog_name $prog_version"
                exit 0
                ;;

            # specific
            --*=*)
                opt "$1"
                ;;
            --*)
                opt "$1=${2+$2}"
                ${2+shift}
                ;;

            # other
            *)
                break
                ;;
        esac
        shift
    done
    : ${run_args:=''} ${build_args:=''}

    # post
    parse_args_post "$@"

    # sanitize environment
    unset -f usage arg
    # rearm for next calls
    parse_args_init
}

## Docker

# Usage: docker_rm
docker_rm()
{
    : ${name:?\$name is not defined}

    local hash
    if hash="$(docker ps -a -q -f "name=$name" 2>/dev/null)" &&
       [ -n "$hash" ]
    then
        echo "* Attempt to stop and remove container $name ($hash) ..."
        docker stop "$hash" ||:
        docker rm "$hash" ||:
    fi
}

# Usage: docker_pull
docker_pull()
{
    : ${image:?\$image is not defined}

    if [ -z "$no_update" ]; then
        echo "* Pull from registry $image ..."
        docker pull "$image"
    fi
}

# Usage: docker_volume_rm <name>...
docker_volume_rm()
{
    local v=' none'

    echo -n '* Remove volume(s)'
    while [ $# -gt 0 ]; do
        if [ -n "$1" ]; then
            {
                # Volume might be shared with other container(s)
                # that should also try to remove it. Last user
                # will successfully remove it.
                docker volume inspect "$1" &&
                docker volume rm "$1" &&
                    v='' || v='!'
            } >/dev/null 2>&1
            echo -n " $v$1"
        fi
        shift
    done

    # echo or echo ' none'
    echo "${v#!}"
}

# Usage: docker_volume <name!path[!opts[!/mpath|...]]>...
docker_volume()
{
    : ${image:?\$image is not defined}

    local volumes
    local init_data="${init_data-}"

    # Usage: docker_volume_parse <name!path[!opts[!/mpath|...]]>...
    docker_volume_parse()
    {
        if [ -n "${dvp_i+x}" ]; then
            volumes="${volumes:+$volumes }$((dvp_i += 1))"
            set -- $1
            eval "
                volume_${dvp_i}_name='$1'
                volume_${dvp_i}_path='$2'
                volume_${dvp_i}_opts='${3-}'
                volume_${dvp_i}_cleanup='${4-}'
            "
        else
            local dvp_i=0

            volumes=''
            local ifs="$IFS"
            IFS='!'
            while [ $# -gt 0 ]; do
                if [ -n "$1" ] && [ -z "${1##*!*}" ]; then
                    docker_volume_parse "$1"
                fi
                shift
            done
            IFS="$ifs"
        fi
    }
    docker_volume_parse "$@"

    echo -n '* Create volume(s)'
    if [ -n "$volumes" ]; then
        local v v_name v_path v_opts v_cleanup
        for v in $volumes; do
            eval "
                v_name=\"\$volume_${v}_name\"
                v_cleanup=\"\$volume_${v}_cleanup\"
                v_path=\"\$volume_${v}_path\"
            "
            if [ -n "$v_path" ]; then
                v_opts=''
            else
                v_opts='!'
                v_cleanup=''
            fi
            echo -n " $v_opts$v_name"

            if [ -n "$init_data" ]; then
                docker volume rm "$v_name" >/dev/null ||:
            fi
            if [ -n "$v_path" ] &&
               ! docker volume inspect "$v_name" >/dev/null 2>&1
            then
                eval "
                    v_opts=\"\${volume_${v}_opts-}\"
                    [ -z \"\${v_opts##*--opt[ =]*}\" ] ||
                        v_opts=\"--opt '\$v_opts'\"
                "
                eval "
                    docker volume create $v_opts \"\$v_name\" >/dev/null
                "
            fi

            if [ -n "$v_cleanup" ]; then
                while [ -z "${v_cleanup##*/}" ]; do
                    if [ -z "$v_cleanup" ]; then
                        v_cleanup='cleanup'
                    else
                        v_cleanup="${v_cleanup%/}"
                    fi
                done
                [ -z "${v_cleanup##/*[!/]}" ] || v_cleanup='/mnt'

                docker run --rm \
                    --network='none' \
                    --user='root:root' \
                    --entrypoint='find' \
                    --volume="$v_name:$v_cleanup" \
                    "$image" \
                    "$v_cleanup" '-mindepth' '1' '-delete' \
                    #
            fi

            if [ -n "$v_path" ]; then
                run_args="$run_args--volume='$v_name:$v_path' "
            fi

            eval "
                unset volume_${v}_name \
                      volume_${v}_opts \
                      volume_${v}_path \
                      volume_${v}_cleanup
            "
        done
        echo
    else
        echo ' none'
    fi
}

# Usage: docker_volume_init <name!path[!opts[!/mpath|...]]>...
docker_volume_init()
{
    local init_data='1'
    docker_volume "$@" || return
}

# Usage: docker_build ...
docker_build()
{
    : ${name:?\$name is not defined}
    : ${image:?\$image is not defined}

    echo "* Build image $image for container $name ..."

    local args="${1-}" && ${1+shift}
    eval set -- "$args" "\$@"

    docker build "$@" \
        "--network=${network_build:-default}" \
        "--pull=${no_update:-true}${no_update:+false}" \
        "--tag=$image" \
        "${path:-$this_dir/..}" \
    || return
}

# Usage: docker_run ...
docker_run()
{
    : ${name:?\$name is not defined}
    : ${image:?\$image is not defined}

    echo "* Run container $name ..."

    local args="${1-}" && ${1+shift}
    eval set -- "$args" '"$@"'

    case "${network-}" in
        'host'|'none'|'default'|'')
            local ip=''
            ;;
        *)
            ;;
    esac

    docker run "$@" \
        --restart='unless-stopped' \
        --detach='true' \
        --tty='true' \
        --hostname="${_app}" \
        \
        ${network:+--network=$network} \
        ${ip:+--ip=$ip} \
        \
        --name="$name" \
        \
        "$image" \
    || return
}

# Usage: docker_volume_exists <name> [<fmt> ...]
docker_volume_exists()
{
    local func="${FUNCNAME:-docker_volume_exists}"

    local name="${1:?missing 1st arg to ${func}() <name>}" && shift
    if [ -n "${1+x}" ]; then
        local fmt="$1" && shift
    else
        local fmt='' && set --
    fi

    local vol="$(
        docker inspect \
            --type='volume' \
            --format='{{.Name}}' \
            "$name" 2>&1
    )" && [ "$vol" = "$name" ] ||
    error "volume '%s' doesn't exist${fmt:+: $fmt}\n" "$name" "$@" || return
}

# Usage: docker_container_running <name> [<fmt> ...]
docker_container_running()
{
    local func="${FUNCNAME:-docker_container_running}"

    local name="${1:?missing 1st arg to ${func}() <name>}" && shift
    if [ -n "${1+x}" ]; then
        local fmt="$1" && shift
    else
        local fmt='' && set --
    fi

    local pid="$(
        docker inspect \
            --type='container' \
            --format='{{.State.Pid}}' \
            "$name" 2>&1
    )" && [ "$pid" != '0' ] ||
    error "container '%s' isn't running${fmt:+: $fmt}\n" "$name" "$@" || return
}

## MySQL

# Usage: mysql_batch <name> ...
mysql_batch()
{
    local func="${FUNCNAME:-mysql_batch}"

    local name="${1:?missing 1st arg to ${func}() <name>}" && shift

    docker exec -i "$name" mysql --batch "$@" || return
}

# Usage: mysql_test_db <name> ...
mysql_test_db()
{
    echo 'SELECT 0 WHERE 0;' | mysql_batch "$@" >/dev/null 2>&1 || return
}

# Usage: mysql_test_ct <name> <user> <pass> ...
mysql_test_ct()
{
    local func="${FUNCNAME:-mysql_test_ct}"

    local name="${1:?missing 1st arg to ${func}() <name>}" && shift
    local user="${1:?missing 2d arg to ${func}() <user>}" && shift
    local pass="${1:?missing 3rd arg to ${func}() <pass>}" && shift

    local nr_tries="${nr_tries:-30}"
    [ "$nr_tries" -ge 0 ] 2>/dev/null || nr_tries=0

    local n=0 h=" $func() ... wait mysql/mariadb"
    while ! mysql_test_db "$name" --user="$user" --password="$pass" "$@"; do
        if [ $((n += 1)) -lt $nr_tries ]; then
            echo -n "$h $n"
            h=''
            sleep 1
        else
            fatal "container '%s' isn't running or not mysql/mariadb.\n" "$name"
        fi
    done
    echo ' ready'

    return 0
}

## Guacamole

readonly _gua_api_user='guacadmin'
readonly _gua_api_pass='guacadmin'

# Usage: guacamole_config_init
guacamole_config_init()
{
    gua_cfg_cb()
    {
        abort 'gua_cfg_cb() is not redefined!'
    }
}
guacamole_config_init

# Usage: guacamole_config
guacamole_config()
{
    # Skip if guacamole not configured (e.g. no profile)
    [ -n "${gua_ip-}" ] || return 0

    local gua_uri="http://$gua_ip:8080/guacamole/api"
    local gua_authToken=''
    local gua_json_dir="$this_dir/../${_app}/guac"

    # User creds to obtain authToken
    local t="guacamole${inst:+_$inst}"

    eval "local gua_api_user=\"\${${t}_api_user:-\${_gua_api_user}}\""
    eval "local gua_api_pass=\"\${${t}_api_pass:-\${_gua_api_pass}}\""

    # Limit reply size from API
    local gua_api_rsize=1048576

    ! [ "${guacamole_api_rsize:-0}" -gt 0 ] 2>/dev/null ||
        gua_api_rsize="$guacamole_api_rsize"

    # Usage: gua_wait_socket
    gua_wait_socket()
    {
        local nr_tries=30 n=0 h=' (... wait socket'
        while ! safe_curl "$gua_uri/languages" $gua_api_rsize -o '/dev/null'; do
            if [ $((n += 1)) -lt $nr_tries ]; then
                echo -n "$h $n"
                h=''
                sleep 1
            else
                echo -n ')'
                return 1
            fi
        done
        [ -n "$h" ] || echo -n ' ready)'
        return 0
    }
    # Usage: gua_authToken_acquire
    gua_authToken_acquire()
    {
        [ -z "${gua_authToken-}" ] || return 0

        gua_authToken="$(
            safe_curl "$gua_uri/tokens" $gua_api_rsize \
                 -S \
                 -X 'POST' \
                 -H 'Content-Type: application/x-www-form-urlencoded' \
                 -d "username=$gua_api_user&password=$gua_api_pass" | \
            jq -r '.authToken'
        )" && [ -n "${gua_authToken#null}" ] || return
    }
    # Usage: gua_authToken_release
    gua_authToken_release()
    {
        [ -n "${gua_authToken-}" ] || return 0

        safe_curl "$gua_uri/tokens/$gua_authToken" $gua_api_rsize \
             -S -o '/dev/null' \
             -X 'DELETE' &&
        gua_authToken='' ||:
    }
    # Usage: gua_api <req> <api> [<curl(1)-options>]
    gua_api()
    {
        local func="${FUNCNAME:-gua_api}"

        : ${gua_authToken:?${func}: authToken must be acquired first!}

        local req="${1:?missing 1st arg to ${func}() <req>}" && shift
        local api="${1:?missing 2d arg to ${func}() <api>}" && shift

        local ds="${gua_api_data_source:-mysql}"
        local data=''
        local token="${gua_authToken}"

        api="${api#/}"

        if [ -z "${api##*@*@*}" ]; then
            api="${api%/@*@*}$(
                # Make sure there is single @name@
                name="${api#*@}" && name="${name%@*}"
                    [ -n "${name##*@*@*}" ] ||
                abort '%s: more than one or empty @name@ in <api>\n' "$func"

                # Search for specific name from entire list
                api="${api%%/*}" &&
                    [ -n "${api##*@*@*}" ] ||
                abort '%s: @name@ in basic API endpoint of <api>\n' "$func"

                "$func" 'GET' "$api" | \
                    jq -r ".[]|select(.name == \"$name\")|\"/\" + .identifier"
            )${api#*@*@}" || return
        fi

        case "$req" in
            'POST'|'PUT'|'PATCH')
                data='application/json'
                ;;
            'DELETE')
                set -- -o '/dev/null' "$@"
                ;;
            'GET')
                ;;
            'UPDATE')
                if local t="${api%/*}" && [ -z "${t%%*/*}" ]; then
                    echo >&2 "${func}: $req only '/<endp>/<param> API level"
                    return 1
                fi
                if [ -z "${api%%*/*}" ] &&
                   [ -n "$("$func" 'GET' "$api" | sed -ne '/"NOT_FOUND"/!p')" ]
                then
                    "$func" 'PUT' "$api" "$@" || return
                else
                    "$func" 'POST'  "$t" "$@" || return
                fi
                return 0
                ;;
            *)
                echo >&2 "${func}: unsupported HTTP method\n"
                return 1
                ;;
        esac

        safe_curl "$gua_uri/session/data/$ds/$api?token=$token" $gua_api_rsize \
            -S \
            -X "$req" \
            ${data:+-H "Content-Type: $data" -d '@-'} \
            "$@" ||
        return
    }

    local gua_rc=0

    echo -n '* Configuring Guacamole'

    if gua_wait_socket &&
       gua_authToken_acquire
    then
        gua_cfg_cb || gua_rc=$?

        gua_authToken_release
    else
        gua_rc=$?
        echo -n ' skipped'
    fi

    echo

    # sanitize environment
    unset -f gua_wait_socket gua_authToken_acquire gua_authToken_release gua_api
    # rearm for next calls
    guacamole_config_init

    return $gua_rc
}

# Usage: read_profile_guacamole [<var>...]
read_profile_guacamole()
{
    local t="guacamole${inst:+_$inst}"

    eval "local ${t}_ip"
    # $guacamole_api_user, $guacamole_api_pass and others,
    # if given as arguments here, are exposed to the caller

    read_profile_nocommon_or_bail "$t" \
        'api_user' 'api_pass' \
        'ip' \
        "$@" \
        #

    if [ "$app" = "$t" ]; then
        # $ip as default if called from guacamole
        # with empty or no profile
        eval "gua_ip=\"\${${t}_ip:-\$ip}\""
    else
        # assert due to readonly if profile read
        # multiple times
        eval "readonly gua_ip=\"\${${t}_ip-}\""
    fi
}
gua_ip=''

## Profile

readonly profiles_dir='/var/local/docker'

# Usage: read_profile <name> <var>...
read_profile()
{
    local func="${FUNCNAME:-read_profile}"

    local name="${1:?missing 1st arg to ${func}() <name>}" && shift
    local profile="$profiles_dir/$name/profile"
    local rc=0

    echo "* Load container information from $profile"

    eval $(
        # Source in subshell to not pollute environment
        if [ -r "$profile" ] && . "$profile" >/dev/null 2>&1 ||
           [ -n "${__read_profile_bail__+x}" ]
        then
            [ -n "${__read_profile_nocommon__+x}" ] ||
            eval "
                printf '%s\n' \
                    \"${name}_name='\${${name}_name-}'\" \
                    \"${name}_image='\${${name}_image-}'\" \
                    \"${name}_network='\${${name}_network-}'\" \
                    \"${name}_ip='\${${name}_ip-}'\" \
                    #
            "

            while [ $# -gt 0 ]; do
                if [ -n "${1##*[!a-zA-Z0-9_]*}" ] &&
                    t="${1#${name}_}" && [ -n "$t" ] && t="${name}_${t}"
                then
                    eval "
                        if [ -n \"\${$t+x}\" ]; then
                            t=\"\$t='\${$t}'\"
                        else
                            t=\"unset '$t'\"
                        fi
                        printf '%s;\n' \"\$t\"
                    "
                fi
                shift
            done
        else
            echo "rc=$?"
        fi
    )

    return $rc
}

# Usage: read_profile_or_fail
read_profile_or_fail()
{
    read_profile "$@" || fatal '"%s" read profile failed.\n' "${1-unknown}"
}
# Usage: read_profile_or_bail
read_profile_or_bail()
{
    local __read_profile_bail__=1
    read_profile "$@"
}

# Usage: read_profile_nocommon
read_profile_nocommon()
{
    local __read_profile_nocommon__=1
    read_profile "$@" || return
}
# Usage: read_profile_nocommon_or_fail
read_profile_nocommon_or_fail()
{
    local __read_profile_nocommon__=1
    read_profile_or_fail "$@"
}
# Usage: read_profile_nocommon_or_bail
read_profile_nocommon_or_bail()
{
    local __read_profile_nocommon__=1
    read_profile_or_bail "$@"
}

# Usage: write_profile <name> <var>...
write_profile()
{
    local func="${FUNCNAME:-write_profile}"

    local name="${1:?missing 1st arg to ${func}() <name>}" && shift
    local profile="$profiles_dir/$name/profile"
    local rc=0

    echo "* Store container information in $profile"

    install -d -m0700 "${profile%/*}" && {
        local _umask="$(umask)"
        umask 0077

        echo '# DO NOT MODIFY. THIS FILE GENERATED AUTOMATICALLY BY'
        echo '# SCRIPT AND COULD BE OVERWRITTEN ON IT'\''S NEXT RUN.'
        echo

        [ -n "${__write_profile_nocommon__+x}" ] ||
        eval "
            printf '%s\n' \
                \"\${name}_name='\$${name}_name'\" \
                \"\${name}_image='\$${name}_image'\" \
                \"\${name}_network='\$${name}_network'\" \
                \"\${name}_ip='\$${name}_ip'\" \
                #
        "

        local t
        while [ $# -gt 0 ]; do
            if [ -n "${1##*[!a-zA-Z0-9_]*}" ] &&
               t="${1#${name}_}" && [ -n "$t" ] && t="${name}_${t}"
            then
                eval "
                   v=\"\${$t-}\"
                   v=\"\$(printf '%s\n' \"\$v\" | sed -e \"s,','\\\\\\'',g\")\"
                   printf '%s\n' \"\$t='\$v'\"
                "
            fi
            shift
        done

        umask "${_umask}"
    }  >"$profile" || rc=$?

    return $rc
}

# Usage: write_profile_or_fail
write_profile_or_fail()
{
    write_profile "$@" || fatal '"%s" write profile failed.\n' "${1-unknown}" 
}
# Usage: write_profile_or_bail
write_profile_or_bail()
{
    write_profile "$@" ||:
}

# Usage: write_profile_nocommon
write_profile_nocommon()
{
    local __write_profile_nocommon__=1
    write_profile "$@" || return
}
# Usage: write_profile_nocommon_or_fail
write_profile_nocommon_or_fail()
{
    local __write_profile_nocommon__=1
    write_profile_or_fail "$@"
}
# Usage: write_profile_nocommon_or_bail
write_profile_nocommon_or_bail()
{
    local __write_profile_nocommon__=1
    write_profile_or_bail "$@"
}

# Usage: sysprep_profile <name> [<sed(1) options>...]
sysprep_profile()
{
    local func="${FUNCNAME:-sysprep_profile}"

    local name="${1:?missing 1st arg to ${func}() <name>}" && shift
    local profile="$profiles_dir/$name/profile"

    # Be extra verbose since this is security sensitive operation
    # and having more precise view on what's going on is desired.

    echo -n "* Prepare profile for deployment in $profile "

      if [ ! -e "$profile" ]; then
        # There might be broken symlink
        rm -f "$profile" ||:
        echo 'skipped, profile does not exist'
    elif [ ! -f "$profile" ]; then
        echo 'skipped, profile not a regular file'
    elif [ ! -r "$profile" ]; then
        echo 'skipped, profile not readable'
    elif [ ! -s "$profile" ]; then
        echo 'skipped, profile empty'
    else
        # Remove sensitive information like passwords,
        # passphrases and NFS share configurations.
        sed -i "$profile" \
            -e '/^.\+_pass\(w\(or\)\?d\)\?=/d' \
            -e '/^.\+_opts=.*\Wtype=nfs\W/d' \
            "$@" \
            #
        echo 'finished'
    fi
}

################################################################################

# Set program name unless already set
if [ -z "${prog_name-}" ]; then
    if [ -n "${this-}" ]; then
        prog_name="${this##*/}"
    else
        prog_name="${this_prog:-libdeploy.sh}"
    fi
fi
prog_version='0.5'

# Verbosity: report errors by default
[ -n "${V-}" ] && [ "$V" -le 0 -o "$V" -ge 0 ] 2>/dev/null || V=1

# Must have $app defined
[ -n "${app-}" ] && [ -n "${app##*[!a-zA-Z0-9_]*}" -a -n "${app##[0-9]*}" ] ||
    abort 'Application name must follow shell variable naming rules\n'

# Optionally have $inst defined
readonly _app="$app"

[ -z "${inst-}" ] || [ -z "${inst##*[!a-zA-Z0-9_]*}" ] && inst='' ||
    app="${app}_${inst}"

# Profile and profile directory
[ -n "${host-}" ] ||
host="$(hostname -s 2>/dev/null)" && [ -n "$host" ] ||
    fatal 'cannot get short host name for host directory\n'

host_dir="$(cd -P "$this_dir/libdeploy/.." && echo "$PWD")" &&
host_dir="$host_dir/hosts/$host" && [ -d "$host_dir" ] ||
    fatal 'host directory "%s" does not exist\n' "$host"

# Must be started by root (uid 0)
[ "$(id -u)" = 0 ] ||
    abort 'Only root (uid 0) can use this service\n'

# Initialize profile '_' if needed
_()
{
    __host="${host}" &&
    __host="${__host##(none)}"

    __domain="$(hostname -d)" &&
    __domain="${__domain##(none)}"

    __fqdn="$(hostname -f)"

    local t="${inst:+_$inst}"

    if [ -n "$t" ]; then
        eval "local ${t}_host"
        eval "local ${t}_domain"
        eval "local ${t}_fqdn"
    fi

    if read_profile_nocommon "${t:-_}" \
        'host' 'domain' 'fqdn'
    then
        if [ -n "$t" ]; then
            eval "__host=\"\${${t}_host:-\${__host}}\""
            eval "__domain=\"\${${t}_domain:-\${__domain}}\""
            eval "__fqdn=\"\${${t}_fqdn:-\${__fqdn}}\""
        fi
    fi

    if [ -n "$t" ]; then
        eval "${t}_host=\"\${__host}\""
        eval "${t}_domain=\"\${__domain}\""
        eval "${t}_fqdn=\"\${__fqdn}\""
    fi

    write_profile_nocommon_or_fail "${t:-_}" \
        'host' 'domain' 'fqdn' \
        #

    unset -f _
}
_

[ -z "${__fqdn##$__host.$__domain}" ] ||
    fatal '"%s" is not consistent, check "_" profile contents\n' "${__fqdn}"
