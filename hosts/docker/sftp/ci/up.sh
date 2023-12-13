#!/bin/sh

# Requires: cat(1)

# Application
app='sftp'

# Network
network='nft-isolated'
ip='192.0.2.244'

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
    hostkeys_volume_name="$app.hostkeys" \
    hostkeys_volume_path='/etc/ssh/hostkeys' \
    hostkeys_volume_opts='size=8M' \
    \
    nfs_volume_name="$app.nfs" \
    \
    nfs_archive_name="$app.archive" \
    nfs_archive_path="$data_dir/Archive:ro,nocopy" \
    \
    nfs_errors_name="$app.errors" \
    nfs_errors_path="$data_dir/Errors:ro,nocopy" \
    #

# Usage: parse_args_usage
parse_args_usage()
{
    cat <<EOF

  for system:
    --timezone=$timezone
        Timezone from /usr/share/zoneinfo/$timezone to configure

  for sftp:
    --user=$user
        User name used for SFTP login
    --user_passwd=$user_passwd
        User password used for SFTP login

    --nfs_volume_path=$nfs_volume_path
        Docker volume mountpoint inside container.
    --nfs_volume_opts=$nfs_volume_opts
        Docker volume driver specific options (e.g. --opt type=btrfs
        --opt device=/dev/sda1).

    --nfs_archive_opts=$nfs_archive_opts
        Docker volume driver specific options (e.g. --opt type=btrfs
        --opt device=/dev/sda1).
    --nfs_errors_opts=$nfs_errors_opts
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

    eval "local ${app}_user"
    eval "local ${app}_user_passwd"

    eval "local ${app}_volume_nfs_path"
    eval "local ${app}_volume_nfs_opts"

    eval "local ${app}_archive_nfs_opts"
    eval "local ${app}_errors_nfs_opts"

    read_profile_or_bail "$app" \
        'timezone' \
        'user' 'user_passwd' \
        'volume_nfs_path' 'volume_nfs_opts' \
        'archive_nfs_opts' 'errors_nfs_opts' \
        #

    # network
    eval "network=\"\${${app}_network:-\$network}\""
    eval "ip=\"\${${app}_ip:-\$ip}\""

    # system
    eval "timezone=\"\${${app}_timezone:-US/Eastern}\""

    # sftp
    eval "user=\"\${${app}_user:-exchange}\""
    eval "user_passwd=\"\${${app}_user_passwd:-}\""

    eval "nfs_volume_path=\"\${${app}_volume_nfs_path:-\$data_dir}\""

    local opt1="--opt 'type=nfs'"
    local opt2="--opt 'o=addr=127.0.0.1,\
vers=3,proto=tcp,port=2049,mountport=2049,nodev,noexec'"
    local opt3="--opt 'device=:/mnt'"

    eval "nfs_volume_opts=\"\${${app}_volume_nfs_opts:-\$opt1 \$opt2 \$opt3}\""

    local opt2="--opt 'o=addr=127.0.0.1,\
vers=3,proto=tcp,port=2049,mountport=2049,nodev,noexec,ro'"
    local opt3="--opt 'device=:/mnt/Archive'"

    eval "nfs_archive_opts=\"\${${app}_archive_nfs_opts:-\$opt1 \$opt2 \$opt3}\""

    local opt2="--opt 'o=addr=127.0.0.1,\
vers=3,proto=tcp,port=2049,mountport=2049,nodev,noexec,ro'"
    local opt3="--opt 'device=:/mnt/Errors'"

    eval "nfs_errors_opts=\"\${${app}_errors_nfs_opts:-\$opt1 \$opt2 \$opt3}\""
}

# Usage: parse_args_opt --<name>=[<value>]
parse_args_opt()
{
    case "$1" in
        # system
        --timezone=*)
            arg "$1" 'non-empty-value'
            ;;

        # sftp
        --user=*|--user_passwd=*)
            arg "$1" 'non-empty-value'
            ;;

        --nfs_volume_path=*|--nfs_volume_opts=*)
            arg "$1" 'non-empty-value'
            ;;

        --nfs_archive_opts=*|--nfs_errors_opts=*)
            arg "$1" 'non-empty-value'
            ;;

        # error
        *)
            ! :
            ;;
    esac
}

# Usage: parse_args_post ...
parse_args_post()
{
    parse_args__post "$@"

    # Hack path to keep sshd_config(5) ChrootDirectory option happy
    # with root-owned pathname directories and not writable by any
    # other user or group.
    #
    # See Dockerfile for sed(1) expression "s,@data_dir@,${data_dir%/*}".
    #
    #  /data/target  1> /data/target 2> /data/target
    #  /data/target/ 1> /data/target 2> /data/target
    #  /data         1> /data        2> /data/.
    #  /data/        1> /data        2> /data/.
    #  /             1> ''           2> /./.
    #  data/target   1> data/target  2> data/target
    #  data          1> data         2> data/.
    #  data/         1> data         2> data/.

    # 1> Stip tailing '/'
    local t
    while :; do
        t="${nfs_volume_path%%/}"
        [ "$t" != "$nfs_volume_path" ] || break
        nfs_volume_path="$t"
    done

    # 2> Add '/.'
    if [ -n "${nfs_volume_path##*/*}" -o -z "${nfs_volume_path%/*}" ]; then
       nfs_volume_path="${nfs_volume_path:-/.}/."
    fi
}

# Usage: up ...
up()
{
    local func="${FUNCNAME:-up}"

    # Parse command line arguments
    parse_args "$@"

    # Skip volume(s)
    local sftp_archive_opts="${nfs_archive_opts##*addr=127.0.0.1*}"
    local sftp_errors_opts="${nfs_errors_opts##*addr=127.0.0.1*}"

    ## sftp

    local name="$app"
    local image="$app:$tag"

    : ${user_passwd:=$(pwmake)}

    docker_rm

    docker_build "$build_args" \
        --build-arg=timezone="$timezone" \
        \
        --build-arg=ip="$ip" \
        \
        --build-arg=user_name="$user" \
        --build-arg=crypt_user_passwd="$(crypt "$user_passwd")" \
        --build-arg=data_dir="$nfs_volume_path" \
        #

    docker_volume \
        "$hostkeys_volume_name!$hostkeys_volume_path!$hostkeys_volume_opts" \
        "$nfs_volume_name!$nfs_volume_path!$nfs_volume_opts" \
        ${sftp_archive_opts:+\
          "$nfs_archive_name!$nfs_archive_path!$nfs_archive_opts"} \
        ${sftp_errors_opts:+\
          "$nfs_errors_name!$nfs_errors_path!$nfs_errors_opts"} \
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

    eval "local ${app}_user=\"\$user\""
    eval "local ${app}_user_passwd=\"\$user_passwd\""

    eval "local ${app}_volume_nfs_path=\"\$nfs_volume_path\""
    eval "local ${app}_volume_nfs_opts=\"\$nfs_volume_opts\""

    eval "local ${app}_archive_nfs_opts=\"\$nfs_archive_opts\""
    eval "local ${app}_errors_nfs_opts=\"\$nfs_errors_opts\""

    write_profile_or_fail "$app" \
        'timezone' \
        'user' 'user_passwd' \
        'volume_nfs_path' 'volume_nfs_opts' \
        'archive_nfs_opts' 'errors_nfs_opts' \
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

    ## sftp

    docker_rm

    docker_volume_rm \
        "$hostkeys_volume_name" \
        "$nfs_volume_name" \
        "$nfs_archive_name" \
        "$nfs_errors_name" \
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
