#!/bin/sh -ue

# Requires: mountpoint(1), install(1), chroot(8), lftp(1)

# Set program name unless already set
prog_name="${0##*/}"
prog_name="${prog_name%\.sh}"

# Verbosity: report errors by default
[ -n "${V-}" ] && [ "$V" -le 0 -o "$V" -ge 0 ] 2>/dev/null || V=1

# Normalize umask(1)
umask 0022

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
msg0() { msg "$@" >&2 || return 0; }

# Usage: fatal <fmt> ...
fatal()
{
    local rc=$?
    printf >&2 -- '%s: ' "$prog_name"
    msg "$@" >&2
    exit $rc
}

# Usage: mirrorer <surl> <tdir> ...
mirrorer()
{
    local func="${FUNCNAME:-mirrorer}"

    local surl="${1:?missing 1st arg to ${func}() <surl>}" && shift
    local tdir="${1:?missing 2d arg to ${func}() <tdir>}" && shift

    local rc=0

    msg0 '* Mirroring data from "%s" to "%s"\n' "$surl" "$tdir"

    # Note that chroot(8) --userspec= doesn't prepare user session
    # in normal sense like login(1) or su(1) does.
    #
    # Thus at least we set HOME= manually to let lftp(1) find ~/.netrc
    # and change current working directory (cwd) to users home (~).
    cd ~@user@ && HOME="$PWD" \
        chroot --userspec='@user@' \
               --skip-chdir '/' \
        lftp -c mirror \
            --verbose \
            --continue \
            --delete \
            --no-overwrite \
            --no-recursion \
            --no-symlinks \
            --no-perms \
            --skip-noaccess \
            --exclude='@inst@' \
            "$surl" "$tdir" \
            #

    msg0 '* Finished\n'

    return $rc
}

# Usage: daemon <instance> ...
daemon()
{
    local func="${FUNCNAME:-daemon}"

    local instance="${1:?missing 1st arg to ${func}() <instance>}" && shift

    # Usage: invoke ...
    invoke()
    {
        local rc=0

        if [ "$target/@inst@" -ef "$target" ]; then
            "$instance" "$@" || rc=$?
        else
            msg '< external target "%s" not initialized\n' "$target" || rc=$?
        fi

        return $rc
    }

    if [ -n "${_mirrorer_oneshot+x}" ]; then
        local rc=0
        invoke "$@" || rc=$?
        return $rc
    fi

    # Skip first run on container (re)start.
    local inited="/dev/.$instance"
    if [ -d "$inited" ]; then
        invoke "$@" ||:
    else
        msg0 '* Initialize application\n'

        if install -d "$inited"; then
            msg0  '> successfully initialized\n'
        else
            fatal '< failed to initialize\n'
        fi
    fi

    msg0 '* Waiting for next run (sleeping)\n'

    local t
    while read t; do
        :
    done
}

################################################################################

target='@target@'
url='@lftp_url@'

msg0 '* Establish source and destination directories\n'

t="$(cd -L "$target" 2>/dev/null && echo "$PWD")" && target="$t" ||
    fatal '< cannot cd to target directory "%s"\n' "$target"
unset t

mountpoint -q "$target" ||
    fatal '< external target "%s" not mounted\n' "$target"

# See how we called
case "$prog_name" in
    'mirrorer')
        daemon mirrorer "$url" "$target" "$@" || exit
        ;;
    *)
        fatal 'Program expected to be called as "%s", not "%s"\n' \
            'mirrorer' "$prog_name" \
            #
        ;;
esac

exit 0
