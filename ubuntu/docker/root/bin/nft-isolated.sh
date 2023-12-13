#!/bin/sh

# Requires: docker(1), expr(1)

prog_name="${0##*/}"

suffix="${inst:+_$inst}"

################################################################################

# Set option(s)
set -e
set -u

## Enable debug/trace
#exec 2>"/tmp/${0##*/}.debug.$(date '+%s.%N')"
#set >&2
#set -x

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
V=1

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

# Usage: network_create_bridge <name> <subnet> [<mtu>]
network_create_bridge()
{
    local func="${FUNCNAME:-network_create_bridge}"

    local name="${1:?missing 1st arg to ${func}() <name>}"
    [ -n "${name##*[.:/]*}" ] || return 1

    local subnet="${2:?missing 2d arg to ${func}() <subnet>}"
    [ -n "${subnet##*[!0-9./]*}" -a -z "${subnet##*.*[0-9]/[0-9]*}" ] || return 2

    local gateway="${subnet%/*}" && gateway="${gateway##*.}"
    [ -n "${gateway##*[!0-9]*}" ] || return 3
    gateway="${subnet%.*/*}.$((gateway + 1))"

    local mtu="${3:-65534}"
    [ "${mtu}" -ge '1500' -a "${mtu}" -le '65534' ] 2>/dev/null ||
        mtu='65534'

    local iface="$name"
    [ "${#iface}" -le 15 ] ||
        iface="$(expr substr "$iface" 1 8)-$(($$ % 131072))"
    # nft-comm-`pid mod 131072'
    # nft-isol-`pid mod 131072'

    docker network create --driver='bridge' \
        --subnet="$subnet" \
        -o 'com.docker.network.bridge.enable_icc=true' \
        -o 'com.docker.network.bridge.enable_ip_masquerade=false' \
        -o "com.docker.network.bridge.host_binding_ipv4=$gateway" \
        -o "com.docker.network.bridge.name=$iface" \
        -o "com.docker.network.driver.mtu=$mtu" \
        "$name" ||
    return
}

# Usage: network_rm <name>
network_rm()
{
    local func="${FUNCNAME:-network_rm}"

    local name="${1:?missing 1st arg to ${func}() <name>}"

    docker network rm "$name" || return
}

################################################################################

# Bridge(s)
readonly v_community='nft-community'
readonly v_isolated='nft-isolated'

# Usage: usage
usage()
{
    local rc=$?
    local fd

    [ $rc -eq 0 ] && fd=1 || fd=2

    cat >&$fd <<EOF
Usage: $prog_name {add|del} [options]

Options and their defaults:
    --net=$net
        Network prefix in CIDR notation to configure.
    --mtu=${mtu:-<max_supported>}
        Maximum Transmit Unit (MTU) to configure.

    --help, --usage
        This help/usage message

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

mtu=''

iface="${prog_name%.sh}"
case "$iface" in
    "$v_community")
        net='192.0.2.128/26'
        ;;
    "$v_isolated")
        net='192.0.2.192/26'
        ;;
    *)
        fatal 'Must be called (i.e. argv0) as "%s", or "%s" not as "%s"\n' \
            "$v_community" "$v_isolated" "$prog_name"
        ;;
esac

cmd="${1-}"
case "$cmd" in
    'add'|'del')
        shift
        ;;
    --help|--usage)
        usage
        ;;
    *)
        fatal 'Must be either "%s" or "%s" command, not "%s"\n' \
            'add' 'del' "$cmd"
        ;;
esac

while [ $# -gt 0 ]; do
    case "$1" in
        --net=*|--mtu=*)
            arg "$1" 'non-empty-value'
            ;;
        --net|--mtu)
            arg "$1=${2-}" 'non-empty-value'
            ${2+shift}
            ;;

        # common
        --help|--usage)
            usage
            ;;

        # other
        *)
            ! : || usage
            ;;
    esac
    shift
done

iface="$iface$suffix"
case "$cmd" in
    'add')
        network_create_bridge "$iface" "$net" "$mtu"
        ;;
    'del')
        network_rm "$iface"
        ;;
esac

exit 0
