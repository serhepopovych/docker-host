#!/bin/sh

# Requires: sed(1), rm(1), install(1)

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

app="${this##*/}"
app="${app%.sh}"

# Helpers
. "$this_dir/libdeploy/sh"

################################################################################

# Containers storage
readonly containers="$profiles_dir/_${inst-}/containers"

# Usage: ct_list [<var>]
ct_list()
{
    # Install default configuration file unless there is specific
    if [ ! -r "$containers" ]; then
        t="$host_dir/_/${containers##*/}"
        [ -f "$t" ] || exit

        rm -f "$containers" ||:
        install -D -m 0600 -o root -g root "$t" "$containers"
    fi

    # Source in subshell to not pollute environment
    eval $(
        {
            readonly v_pat='[a-z][-a-z0-9_]*'
            readonly q="[\"']\?"

            sed "$containers" \
                -n \
                -e "s,^container_\([0-9]\+\)=${q}\(${v_pat}\)${q}$,\1 \2,p" \
                #
        } | {
            [ -r "$containers" ] && . "$containers" >/dev/null || exit

            c=0

            while read -r id _; do
                c=$((c += 1))
                eval "ct_${c}=\"\${container_${id}-}\""
            done

            ct_min=1
            ct_max=$c

            t=''

            if [ -n "${__ct_list_rev__+x}" ]; then
                while [ $ct_max -ge $ct_min ]; do
                    eval "t=\"\${t:+\$t }\${ct_${ct_max}}\""
                    : $((ct_max -= 1))
                done
            else
                while [ $ct_min -le $ct_max ]; do
                    eval "t=\"\${t:+\$t }\${ct_${ct_min}}\""
                    : $((ct_min += 1))
                done
            fi

            printf '%s;\n' "local t='$t'"
        }
    )

    if [ -n "${1+x}" ]; then
        eval "$1='$t'"
    else
        echo "$t"
    fi
}

# Usage: ct_list_rev
ct_list_rev()
{
    local __ct_list_rev__='1'
    ct_list "$@" || return
}

# Usage: update ...
update()
{
    local __ct__
    ct_list '__ct__'

    local t
    for t in \
        ${__ct__} \
        #
    do
        "$host_dir/$t/ci/up.sh" "$@"
    done

    prune

    exec "$this_dir/users.sh"

    # Never reached
    exit 123
}

# sysprep ...
sysprep()
{
    local __ct__
    ct_list_rev '__ct__'

    local t
    for t in \
        ${__ct__} \
        #
    do
        "$host_dir/$t/ci/down.sh" "$@"
    done

    exit 0
}

# Usage: prune ...
prune()
{
    local t
    for t in \
        'builder' \
        'image' \
        #
    do
        docker "$t" prune --all --force ||:
    done
}

# See how we've called
case "$prog_name" in
    'update.sh')
        update "$@"
        ;;
    'sysprep.sh')
        sysprep "$@"
        ;;
    'prune.sh')
        prune "$@"
        ;;
    *)
        printf >&2 '%s: Must be called as "%s" or "%s", but alled as "%s"\n' \
            "$this_prog" 'update.sh' 'sysprep.sh' "$prog_name" \
            #
        exit 1
        ;;
esac
