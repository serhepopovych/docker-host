#!/bin/sh

# Requires: cat(1)

# Application
app='mariadb'

# Network
network='nft-isolated'
ip='192.0.2.209'

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
    mdb_volume_name="$app.data" \
    mdb_volume_path='/var/lib/mysql' \
    #

# Usage: parse_args_usage
parse_args_usage()
{
    cat <<EOF

  for mariadb:
    --mdb_root_password=${mdb_root_password:-<random>}
        MariaDB root user password or random if empty.
    --mdb_volume_opts=$mdb_volume_opts
        Docker volume driver specific options (e.g. size=2G for local driver).
EOF
}

# Usage: parse_args_pre ...
parse_args_pre()
{
    # tag
    tag='lts'

    # read profile
    eval "local ${app}_name"
    eval "local ${app}_image"
    eval "local ${app}_network"
    eval "local ${app}_ip"

    eval "local ${app}_pass"

    eval "local ${app}_volume_opts"

    read_profile_or_bail "$app" \
        'pass' \
        'volume_opts' \
        #

    # network
    eval "network=\"\${${app}_network:-\$network}\""
    eval "ip=\"\${${app}_ip:-\$ip}\""

    # mariadb
    eval "mdb_root_password=\"\${${app}_pass-}\""
    eval "mdb_volume_opts=\"\${${app}_volume_opts:-size=2G}\""
}

# Usage: parse_args_opt --<name>=[<value>]
parse_args_opt()
{
    case "$1" in
        # mariadb
        --mdb_root_password=*|--mdb_volume_opts=*)
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

    ## mariadb

    local name="$app"
    local image="${_app}:$tag"

    : ${mdb_root_password:=$(pwmake)}

    docker_rm
    docker_pull

    docker_volume \
        "$mdb_volume_name!$mdb_volume_path!$mdb_volume_opts" \
        #

    docker_run "$run_args" \
        --env="MARIADB_ROOT_PASSWORD=$mdb_root_password" \
        --env='MARIADB_ROOT_HOST=localhost' \
        #

    # write profile
    eval "local ${app}_name=\"\$name\""
    eval "local ${app}_image=\"\$image\""
    eval "local ${app}_network=\"\$network\""
    eval "local ${app}_ip=\"\$ip\""

    eval "local ${app}_host=\"\$name\""
    eval "local ${app}_user='root'"
    eval "local ${app}_pass=\"\$mdb_root_password\""

    eval "local ${app}_volume_opts=\"\$mdb_volume_opts\""

    write_profile_or_fail "$app" \
        'host' 'user' 'pass' \
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

    read_profile_nocommon_or_fail "$app" \
        'name' 'image' \
        #

    eval "local name=\"\${${app}_name}\""
    eval "local image=\"\${${app}_image}\""

    ## mariadb

    docker_rm

    docker_volume_rm \
        "$mdb_volume_name" \
        #

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
