#!/bin/sh

# Requires: cat(1)

# Application
app='nginx'

# Network
network='nft-isolated'
ip='192.0.2.242'

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
    cache_volume_path='/var/cache/nginx' \
    #

# Usage: parse_args_usage
parse_args_usage()
{
    cat <<EOF

  for system:
    --timezone=$timezone
        Timezone from /usr/share/zoneinfo/$timezone to configure

  for nginx:
    --cache_volume_opts=$cache_volume_opts
        Docker volume driver specific options (e.g. size=256M for local driver)

  for certbotsh:
    --cbtsh_http_url=$cbtsh_http_url
        URL to fetch PKCS#12 file from
    --cbtsh_http_auth=$cbtsh_http_auth
        Letsencrypt user password for HTTP authentication http_url
    --cbtsh_ph=$cbtsh_ph
        Passphrase to decrypt PKCS#12 contents
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

    eval "local ${app}_volume_cache_opts"

    eval "local ${app}_cbtsh_http_url"
    eval "local ${app}_cbtsh_http_auth"
    eval "local ${app}_cbtsh_ph"

    read_profile_or_bail "$app" \
        'timezone' \
        'volume_cache_opts' \
        'cbtsh_http_url' 'cbtsh_http_auth' 'cbtsh_ph' \
        #

    # network
    eval "network=\"\${${app}_network:-\$network}\""
    eval "ip=\"\${${app}_ip:-\$ip}\""

    # system
    eval "timezone=\"\${${app}_timezone:-US/Eastern}\""

    # nginx
    eval "cache_volume_opts=\"\${${app}_volume_cache_opts:-size=2G}\""

    # certbotsh
    eval "cbtsh_http_url=\"https://acme-le.gw.api.\${__domain}/~letsencrypt\""
    eval "cbtsh_http_url=\"\${${app}_cbtsh_http_url:-\$cbtsh_http_url}\""
    eval "cbtsh_http_auth=\"\${${app}_cbtsh_http_auth-}\""
    eval "cbtsh_ph=\"\${${app}_cbtsh_ph-}\""
}

# Usage: parse_args_opt --<name>=[<value>]
parse_args_opt()
{
    case "$1" in
        # system
        --timezone=*)
            arg "$1" 'non-empty-value'
            ;;

        # nginx
        --cache_volume_opts=*)
            arg "$1" 'non-empty-value'
            ;;

        # certbotsh
        --cbtsh_http_url=*|--cbtsh_http_auth=*)
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

    # read profile 'guacamole'
    local t="guacamole${inst:+_$inst}"

    eval "local ${t}_api_user"
    eval "local ${t}_api_pass"
    eval "local ${t}_ip_cm"
    eval "local ${t}_ip_edge"

    read_profile_guacamole \
        'ip_edge' 'ip_cm' \
        #

    eval "local edge_ip=\"\${${t}_ip_edge-}\""

    # read profile 'phpmyadmin'
    local t="phpmyadmin${inst:+_$inst}"

    eval "local ${t}_ip"
    eval "local ${t}_volume_name"

    read_profile_nocommon_or_fail "$t" \
        'ip' \
        'volume_name' \
        #

    eval "local pma_ip=\"\${${t}_ip}\""
    eval "local pma_volume_name=\"\${${t}_volume_name}\""

    local pma_volume_path='/var/www/phpmyadmin'

    docker_volume_exists "$pma_volume_name" || exit

    ## nginx

    local name="$app"
    local image="$app:$tag"

    docker_rm

    docker_build "$build_args" \
        --build-arg=timezone="$timezone" \
        \
        --build-arg=ngx_hostname="${__host}" \
        \
        --build-arg=cbtsh_http_url="$cbtsh_http_url" \
        --build-arg=cbtsh_http_auth="$cbtsh_http_auth" \
        --build-arg=cbtsh_domain="${__fqdn}" \
        --build-arg=cbtsh_ph="$cbtsh_ph" \
        --build-arg=pma_ip="$pma_ip" \
        --build-arg=gua_ip="${gua_ip:-127.0.0.1}" \
        --build-arg=edge_ip="${edge_ip:-127.0.0.1}" \
        #

    docker_volume \
        "$cache_volume_name!$cache_volume_path!$cache_volume_opts" \
        #

    docker_run "$run_args" \
        --volume="$pma_volume_name:$pma_volume_path:ro" \
        #

    # write profile
    eval "local ${app}_name=\"\$name\""
    eval "local ${app}_image=\"\$image\""
    eval "local ${app}_network=\"\$network\""
    eval "local ${app}_ip=\"\$ip\""

    eval "local ${app}_timezone=\"\$timezone\""

    eval "local ${app}_volume_cache_opts=\"\$cache_volume_opts\""

    eval "local ${app}_cbtsh_http_url=\"\$cbtsh_http_url\""
    eval "local ${app}_cbtsh_http_auth=\"\$cbtsh_http_auth\""
    eval "local ${app}_cbtsh_ph=\"\$cbtsh_ph\""

    write_profile_or_fail "$app" \
        'timezone' \
        'volume_cache_opts' \
        'cbtsh_http_url' 'cbtsh_http_auth' 'cbtsh_ph' \
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

    # read profile 'phpmyadmin'
    local t="phpmyadmin${inst:+_$inst}"

    eval "local ${t}_volume_name"

    read_profile_nocommon_or_bail "$t" \
        'volume_name' \
        #

    eval "local pma_volume_name=\"\${${t}_volume_name-}\""

    ## nginx

    docker_rm

    docker_volume_rm \
        "$pma_volume_name" \
        "$cache_volume_name" \
        #

    ## Sanitize profile
    sysprep_profile "$app" \
        -e '/^.\+_cbtsh_\(http_auth\|ph\)=/d' \
        #
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
