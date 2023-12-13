#!/bin/sh

# Requires: cat(1)

# Application
app='mitmproxy'

# Network
network='host'
ip=''

ip_proxy='0.0.0.0'
port_proxy='8080'
ip_webui='192.0.2.1'
port_webui='8081'

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
    data_volume_name="$app.data" \
    data_volume_path='/data' \
    #

# Usage: parse_args_usage
parse_args_usage()
{
    cat <<EOF

  for system:
    --timezone=$timezone
        Timezone from /usr/share/zoneinfo/$timezone to configure

  for mitmproxy:
    --oba_hostname=$oba_hostname
        Hostname to access for onboarding application/CA certificates

    --listen_host=$listen_host
        Proxy server address to bind to
    --listen_port=$listen_port
        Proxy server port to bind to

    --data_volume_opts=$data_volume_opts
        Docker volume driver specific options (e.g. size=1G for local driver).

  for mitmweb:
    --web_host=$web_host
        Bind to address for Web UI
    --web_port=$web_port
        Bind to port for Web UI

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

    eval "local ${app}_oba_hostname"

    eval "local ${app}_listen_host"
    eval "local ${app}_listen_port"

    eval "local ${app}_volume_opts"

    eval "local ${app}_web_host"
    eval "local ${app}_web_port"

    read_profile_or_bail "$app" \
        'timezone' \
        'oba_hostname' \
        'listen_host' 'listen_port' \
        'volume_opts' \
        'web_host' 'web_port' \
        #

    # network
    eval "network=\"\${${app}_network:-\$network}\""
    eval "ip=\"\${${app}_ip:-\$ip}\""

    # system
    eval "timezone=\"\${${app}_timezone:-US/Eastern}\""

    # mitmproxy
    eval "oba_hostname=\"\${${app}_oba_hostname:-mitm.it}\""

    eval "listen_host=\"\${${app}_listen_host:-\$ip_proxy}\""
    eval "listen_port=\"\${${app}_listen_port:-\$port_proxy}\""

    eval "data_volume_opts=\"\${${app}_volume_opts:-size=1G}\""

    # mitmweb
    eval "web_host=\"\${${app}_web_host:-\$ip_webui}\""
    eval "web_port=\"\${${app}_web_port:-\$port_webui}\""
}

# Usage: parse_args_opt --<name>=[<value>]
parse_args_opt()
{
    case "$1" in
        # system
        --timezone=*)
            arg "$1" 'non-empty-value'
            ;;

        # mitmproxy
        --oba_hostname=*)
            arg "$1" 'non-empty-value'
            ;;

        --listen_host=*|--listen_port=*)
            arg "$1" 'non-empty-value'
            ;;

        --data_volume_opts=*)
            arg "$1" 'non-empty-value'
            ;;

        # mitmweb
        --web_host=*|--web_port=*)
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

    ## mitmproxy/mitmweb

    local name="$app"
    local image="$app:$tag"

    docker_rm

    docker_build "$build_args" \
        --build-arg=timezone="$timezone" \
        \
        --build-arg=data_dir="$data_volume_path" \
        \
        --build-arg=oba_hostname="$oba_hostname" \
        \
        --build-arg=listen_host="$listen_host" \
        --build-arg=listen_port="$listen_port" \
        \
        --build-arg=web_host="$web_host" \
        --build-arg=web_port="$web_port" \
        #

    ! (V=0 docker_volume_exists "$data_volume_name") ||
        docker run --rm \
            --network='none' \
            --user='root:root' \
            --entrypoint='install' \
             --volume="$data_volume_name:/mnt" \
            "$image" \
            '-D' '-m' '0644' '-o' 'root' '-g' 'root' \
            "$data_volume_path/.mitmproxy/config.yaml" \
            '/mnt/.mitmproxy/config.yaml' \
            #

    docker_volume \
        "$data_volume_name!$data_volume_path!$data_volume_opts" \
        #

    docker_run "$run_args" \
        #

    # write profile
    eval "local ${app}_name=\"\$name\""
    eval "local ${app}_image=\"\$image\""
    eval "local ${app}_network=\"\$network\""
    eval "local ${app}_ip=\"\$ip\""

    eval "local ${app}_timezone=\"\$timezone\""

    eval "local ${app}_oba_hostname=\"\$oba_hostname\""

    eval "local ${app}_listen_host=\"\$listen_host\""
    eval "local ${app}_listen_port=\"\$listen_port\""

    eval "local ${app}_volume_opts=\"\$data_volume_opts\""

    eval "local ${app}_web_host=\"\$web_host\""
    eval "local ${app}_web_port=\"\$web_port\""

    write_profile_or_fail "$app" \
        'timezone' \
        'oba_hostname' \
        'listen_host' 'listen_port' \
        'volume_opts' \
        'web_host' 'web_port' \
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

    ## mitmproxy/mitmweb

    docker_rm

    docker_volume_rm \
        "$data_volume_name" \
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
