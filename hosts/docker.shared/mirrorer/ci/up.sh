#!/bin/sh

# Requires: cat(1), sed(1), jq(1)

# Application
app='mirrorer'

# Network
network='default'
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
    volume_target_name="$app.target" \
    volume_target_path='/data' \
    #

# Usage: parse_args_usage
parse_args_usage()
{
    cat <<EOF

  for system:
    --timezone=$timezone
        Timezone from /usr/share/zoneinfo/$timezone to configure

  for mirrorer:
    --lftp_url=$lftp_url
        Full URL, including username and path
    --lftp_host=$lftp_host
        Host part of URL
    --lftp_user=$lftp_user
    --lftp_pass=$lftp_pass
        Username and password to authenticate to host

    --volume_target_opts=$volume_target_opts
        Docker volume driver specific options (e.g. --opt type=btrfs
        --opt device=/dev/sda1).
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

    eval "local ${app}_lftp_url"
    eval "local ${app}_lftp_host"
    eval "local ${app}_lftp_user"
    eval "local ${app}_lftp_pass"

    read_profile_or_bail "$app" \
        'timezone' \
        'lftp_url' 'lftp_host' 'lftp_user' 'lftp_pass' \
        'volume_target_opts' \
        #

    # network
    eval "network=\"\${${app}_network:-\$network}\""
    eval "ip=\"\${${app}_ip:-\$ip}\""

    # system
    eval "timezone=\"\${${app}_timezone:-US/Eastern}\""

    # mirrorer
    eval "lftp_url=\"\${${app}_lftp_url:-ftp://ftp.example.com/data}\""
    eval "lftp_host=\"\${${app}_lftp_host:-ftp.example.com}\""
    eval "lftp_user=\"\${${app}_lftp_user:-anonymous}\""
    eval "lftp_pass=\"\${${app}_lftp_pass:-anonymous@example.com}\""

    local opt1="--opt 'type=nfs'"
    local opt2="--opt 'o=addr=127.0.0.1,\
vers=3,proto=tcp,port=2049,mountport=2049,nodev,noexec'"
    local opt3="--opt 'device=:/mnt'"

    eval "volume_target_opts=\"\${${app}_volume_target_opts:-\$opt1 \$opt2 \$opt3}\""
}

# Usage: parse_args_opt --<name>=[<value>]
parse_args_opt()
{
    case "$1" in
        # system
        --timezone=*)
            arg "$1" 'non-empty-value'
            ;;

        # mirrorer
        --lftp_url=*|--lftp_host=*)
            arg "$1" 'non-empty-value'
            ;;
        --lftp_user=*|--lftp_pass=*)
            arg "$1"
            ;;

        --volume_target_opts=*)
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

    ## mirrorer

    local name="$app"
    local image="$app:$tag"

    docker_rm

    docker_build "$build_args" \
        --build-arg=timezone="$timezone" \
        \
        --build-arg=inst="${__host}" \
        \
        --build-arg=lftp_url="$lftp_url" \
        --build-arg=lftp_host="$lftp_host" \
        --build-arg=lftp_user="$lftp_user" \
        --build-arg=lftp_pass="$lftp_pass" \
        #

    docker_volume \
        "$volume_target_name!$volume_target_path!$volume_target_opts" \
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

    eval "local ${app}_lftp_url=\"\$lftp_url\""
    eval "local ${app}_lftp_host=\"\$lftp_host\""
    eval "local ${app}_lftp_user=\"\$lftp_user\""
    eval "local ${app}_lftp_pass=\"\$lftp_pass\""

    eval "local ${app}_volume_target_opts=\"\$volume_target_opts\""

    write_profile_or_fail "$app" \
        'timezone' \
        'lftp_url' 'lftp_host' 'lftp_user' 'lftp_pass' \
        'volume_target_opts' \
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

    ## mirrorer

    docker_rm

    docker_volume_rm \
        "$volume_target_name" \
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
