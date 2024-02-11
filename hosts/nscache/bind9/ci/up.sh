#!/bin/sh

# Requires: cat(1)

# Application
app='bind9'

# Network
network='host'
ip=''

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
    cache_volume_name="$app.cache" \
    cache_volume_path='/var/cache/bind' \
    #

# Usage: parse_args_usage
parse_args_usage()
{
    cat <<EOF

  for system:
    --timezone=$timezone
        Timezone from /usr/share/zoneinfo/$timezone to configure
    --locale=$locale
        Locale from /etc/locale.gen to configure

  for bind9:
    --cache_volume_opts=$cache_volume_opts
        Docker volume driver specific options (e.g. size=256M for local driver)
EOF
}

# Usage: parse_args_pre ...
parse_args_pre()
{
    # tag
    tag='dh'

    # read profile
    eval "local ${app}_name"
    eval "local ${app}_image"
    eval "local ${app}_network"
    eval "local ${app}_ip"

    eval "local ${app}_timezone"
    eval "local ${app}_locale"

    eval "local ${app}_volume_cache_opts"

    read_profile_or_bail "$app" \
        'timezone' 'locale' \
        'volume_cache_opts' \
        #

    # network
    eval "network=\"\${${app}_network:-\$network}\""
    eval "ip=\"\${${app}_ip:-\$ip}\""

    # system
    eval "timezone=\"\${${app}_timezone:-US/Eastern}\""
    eval "locale=\"\${${app}_locale:-en_US.UTF-8}\""

    # bind9
    eval "cache_volume_opts=\"\${${app}_volume_cache_opts:-size=2G}\""
}

# Usage: parse_args_opt --<name>=[<value>]
parse_args_opt()
{
    case "$1" in
        # system
        --timezone=*|--locale=*)
            arg "$1" 'non-empty-value'
            ;;

        # bind9
        --cache_volume_opts=*)
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

    ## bind9

    local name="$app"
    local image="$app:$tag"

    docker_rm

    docker_build "$build_args" \
        --build-arg=host="$host" \
        \
        --build-arg=timezone="$timezone" \
        --build-arg=locale="$locale" \
        #

    docker_volume \
        "$cache_volume_name!$cache_volume_path!$cache_volume_opts" \
        #

    docker_run "$run_args" \
        --init \
        #

    # write profile
    eval "local ${app}_name=\"\$name\""
    eval "local ${app}_image=\"\$image\""
    eval "local ${app}_network=\"\$network\""
    eval "local ${app}_ip=\"\$ip\""

    eval "local ${app}_timezone=\"\$timezone\""
    eval "local ${app}_locale=\"\$locale\""

    # bind9
    eval "local ${app}_volume_cache_opts=\"\$cache_volume_opts\""

    write_profile_or_fail "$app" \
        'timezone' 'locale' \
        'volume_cache_opts' \
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

    ## bind9

    docker_rm

    docker_volume_rm \
        "$cache_volume_name" \
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
