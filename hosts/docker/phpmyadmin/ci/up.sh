#!/bin/sh

# Requires: cat(1)

# Application
app='phpmyadmin'

# Network
network='nft-isolated'
ip='192.0.2.210'

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
    pma_volume_name="$app.www" \
    pma_volume_path='/var/www/html' \
    #

# Usage: parse_args_usage
parse_args_usage()
{
    cat <<EOF

  for phpmyadmin:
    --pma_volume_opts=$pma_volume_opts
        Docker volume driver specific options (e.g. size=256M for local driver).
EOF
}

# Usage: parse_args_pre ...
parse_args_pre()
{
    # tag
    tag='fpm'

    # read profile
    eval "local ${app}_name"
    eval "local ${app}_image"
    eval "local ${app}_network"
    eval "local ${app}_ip"

    eval "local ${app}_volume_opts"

    read_profile_or_bail "$app" \
        'volume_opts' \
        #

    # network
    eval "network=\"\${${app}_network:-\$network}\""
    eval "ip=\"\${${app}_ip:-\$ip}\""

    # phpmyadmin
    eval "pma_volume_opts=\"\${${app}_volume_opts:-size=256M}\""
}

# Usage: parse_args_opt --<name>=[<value>]
parse_args_opt()
{
    case "$1" in
        # phpmyadmin
        --pma_volume_opts=*)
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

    ## phpmyadmin

    local name="$app"
    local image="${_app}:$tag"

    docker_rm
    docker_pull

    docker_volume \
        "$pma_volume_name!$pma_volume_path!$pma_volume_opts!cleanup" \
        #

    docker_run "$run_args" \
        --env="PMA_HOST=$mdb_host" \
        --env="PMA_ABSOLUTE_URI=https://${__fqdn}/phpmyadmin/" \
        --env='HIDE_PHP_VERSION=1' \
        #

    # write profile
    eval "local ${app}_name=\"\$name\""
    eval "local ${app}_image=\"\$image\""
    eval "local ${app}_network=\"\$network\""
    eval "local ${app}_ip=\"\$ip\""

    eval "local ${app}_volume_name=\"\$pma_volume_name\""
    eval "local ${app}_volume_opts=\"\$pma_volume_opts\""

    write_profile_or_fail "$app" \
        'volume_name' 'volume_opts' \
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

    ## phpmyadmin

    docker_rm

    docker_volume_rm \
        "$pma_volume_name" \
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
