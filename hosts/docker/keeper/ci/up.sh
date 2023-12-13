#!/bin/sh

# Requires: cat(1), sed(1), jq(1)

# Application
app='keeper'

# Network
network='none'
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
    data_dir='/data' \
    #
readonly \
    volume_target_path="$data_dir/target" \
    volume_storage_path="$data_dir/storage" \
    #

# Usage: parse_args_usage
parse_args_usage()
{
    cat <<EOF

  for system:
    --timezone=$timezone
        Timezone from /usr/share/zoneinfo/$timezone to configure

  for keeper:
    --glob_files=$glob_files
        Pattern to glob match files in find(1) using -name directive
    --keep_days=$keep_days
        Keep recordings for no longer than specified number of days

    --volume_target_name=$volume_target_name
    --volume_storage_name=$volume_storage_name
        Docker volume name
    --volume_target_opts=$volume_target_opts
    --volume_storage_opts=$volume_storage_opts
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

    eval "local ${app}_glob_files"
    eval "local ${app}_keep_days"

    eval "local ${app}_volume_target_name"
    eval "local ${app}_volume_storage_name"
    eval "local ${app}_volume_target_opts"
    eval "local ${app}_volume_storage_opts"

    read_profile_or_bail "$app" \
        'timezone' \
        'glob_files' 'keep_days' \
        'volume_target_name' 'volume_storage_name' \
        'volume_target_opts' 'volume_storage_opts' \
        #

    # network
    eval "network=\"\${${app}_network:-\$network}\""
    eval "ip=\"\${${app}_ip:-\$ip}\""

    # system
    eval "timezone=\"\${${app}_timezone:-US/Eastern}\""

    # keeper
    eval "glob_files=\"\${${app}_glob_files-*.wav}\""
    eval "keep_days=\"\${${app}_keep_days:-1275}\""

    eval "volume_target_name=\"\${${app}_volume_target_name-}\""
    eval "volume_storage_name=\"\${${app}_volume_storage_name-}\""

    volume_target_name="${volume_target_name:-$app.target}"
    volume_storage_name="${volume_storage_name:-$app.storage}"

    eval "volume_target_opts=\"\${${app}_volume_target_opts:-size=8G}\""

    local opt1="--opt 'type=nfs'"
    local opt2="--opt 'o=addr=127.0.0.1,\
vers=3,proto=tcp,port=2049,mountport=2049,nodev,noexec'"
    local opt3="--opt 'device=:/mnt'"

    eval "volume_storage_opts=\"\${${app}_volume_storage_opts:-\$opt1 \$opt2 \$opt3}\""
}

# Usage: parse_args_opt --<name>=[<value>]
parse_args_opt()
{
    case "$1" in
        # system
        --timezone=*)
            arg "$1" 'non-empty-value'
            ;;

        # keeper
        --glob_files=*|--keep_days=*)
            arg "$1" 'non-empty-value'
            ;;

        --volume_target_name=*|--volume_storage_name=*)
            arg "$1" 'non-empty-value'
            ;;
        --volume_target_opts=*|--volume_storage_opts=*)
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

    ## keeper

    local name="$app"
    local image="$app:$tag"

    docker_rm

    docker_build "$build_args" \
        --build-arg=timezone="$timezone" \
        \
        --build-arg=target="$volume_target_path" \
        --build-arg=storage="$volume_storage_path" \
        \
        --build-arg=inst="${__host}" \
        --build-arg=glob="$glob_files" \
        --build-arg=days="$keep_days" \
        #

    if [ -z "${volume_target_opts##*[!a-zA-Z0-9_]type=*}" ] &&
       [ "$volume_target_opts" = "$volume_storage_opts" ]
    then
        # Let docker mount it twice inside container to keep reference
        # for both volumes until container destroyed.
        docker_volume \
            "$volume_target_name!$data_dir!$volume_target_opts" \
            "$volume_storage_name!${data_dir}_same!$volume_storage_opts" \
            #
    else
        docker_volume \
            "$volume_target_name!$volume_target_path!$volume_target_opts" \
            "$volume_storage_name!$volume_storage_path!$volume_storage_opts" \
            #
    fi

    docker_run "$run_args" \
        --init \
        #

    # write profile
    eval "local ${app}_name=\"\$name\""
    eval "local ${app}_image=\"\$image\""
    eval "local ${app}_network=\"\$network\""
    eval "local ${app}_ip=\"\$ip\""

    eval "local ${app}_timezone=\"\$timezone\""

    eval "local ${app}_glob_files=\"\$glob_files\""
    eval "local ${app}_keep_days=\"\$keep_days\""

    eval "local ${app}_volume_target_name=\"\$volume_target_name\""
    eval "local ${app}_volume_storage_name=\"\$volume_storage_name\""
    eval "local ${app}_volume_target_opts=\"\$volume_target_opts\""
    eval "local ${app}_volume_storage_opts=\"\$volume_storage_opts\""

    write_profile_or_fail "$app" \
        'timezone' \
        'glob_files' 'keep_days' \
        'volume_target_name' 'volume_storage_name' \
        'volume_target_opts' 'volume_storage_opts' \
        #
}

# Usage: down ...
down()
{
    local func="${FUNCNAME:-down}"

    # read profile
    eval "local ${app}_name"
    eval "local ${app}_image"

    eval "local ${app}_volume_target_name"
    eval "local ${app}_volume_storage_name"

    read_profile_nocommon_or_fail "$app" \
        'name' 'image' \
        'volume_target_name' 'volume_storage_name' \
        #

    eval "local name=\"\${${app}_name}\""
    eval "local image=\"\${${app}_image}\""

    eval "local volume_target_name=\"\${${app}_volume_target_name-}\""
    eval "local volume_storage_name=\"\${${app}_volume_storage_name-}\""

    volume_target_name="${volume_target_name:-$app.target}"
    volume_storage_name="${volume_storage_name:-$app.storage}"

    ## keeper

    docker_rm

    docker_volume_rm \
        "$volume_target_name" \
        "$volume_storage_name" \
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
