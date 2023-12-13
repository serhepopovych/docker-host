#!/bin/sh -ue

# Requires: mountpoint(1), find(1), install(1), xargs(1), rm(1), ln(1),
#           sed(1), tmpreaper(1)

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

# Usage: xtee [{<fd>|<file>}...]
xtee()
{
    local t fd

    local fds=''
    for fd in "$@"; do
        [ -n "$fd" ] || continue

        if [ -n "${fd##*[!0-9]*}" ]; then
            # write to <fd>
            fd="&$fd"
        else
            # append to <file>
            fd=">'$fd'"
        fi

        fds="$fds\"$fd\" "
    done
    eval "set -- $fds"

    while read -r t; do
        printf '%s\n' "$t"
        for fd in "$@"; do
            eval "printf '%s\n' \"\$t\" >$fd"
        done
    done
}

# Usage: keeper <sdir> <tdir> <pat> ...
keeper()
{
    local func="${FUNCNAME:-keeper}"

    local sdir="${1:?missing 1st arg to ${func}() <sdir>}" && shift
    local tdir="${1:?missing 2d arg to ${func}() <tdir>}" && shift
    local pat="${1-}" && shift

    local rc=0

    cd "$sdir" >/dev/null || return

    msg0 '* Moving data from "%s" to "%s"\n' "$sdir" "$tdir"

    find "$sdir" \
      ${pat:+-name "$pat" -a} -type f -a -printf "%p %TY/%Tm/%Td/%f\n" | \
         while read p r; do
            d="$tdir/$r"

            if ! [ "$p" -ef "$d" ]; then
                if [ -n "${xdrive+x}" ]; then
                    install -Dpm0644 "$p" "$d" || continue
                else
                    install -d "${d%/*}" && mv -f "$p" "$d" || continue
                fi

                # For xargs ln ...
                printf -- '%s\n' "../${tdir##*/}/$r"

                msg0 '>  from "%s" to "%s"\n' "$p" "$d"
            fi
         done | \
    xargs -r ln ${xdrive+-s} -nf -t "$sdir" || rc=$((rc + $?))

    cd - >/dev/null || rc=$((rc + $?))

    msg0 '* Finished\n'

    return $rc
}

# Usage: reaper <sdir> <tdir> <age> ...
reaper()
{
    local func="${FUNCNAME:-reaper}"

    local sdir="${1:?missing 1st arg to ${func}() <sdir>}" && shift
    local tdir="${1:?missing 2d arg to ${func}() <tdir>}" && shift
    local age="${1:?missing 3rd arg to ${func}() <age>}" && shift

    local rc=0

    msg0 '* Trying to find and remove outdated files in "%s"\n' "$tdir"

    # Note that "tee /dev/stderr" may not work (e.g. when /dev/stderr a socket)
    exec 5>&1

    tmpreaper --showdeleted --mtime "${age%d}d" "$tdir" | \
       xtee 5 | \
       sed -n -e "s,^rm\s\+\([^/]\+/\)\+\([^/]\+\)$,$sdir/\2,p" | \
    xargs rm -f || rc=$((rc + $?))

    exec 5>&-

    find "$tdir" -type d -a -empty -a -delete || rc=$((rc + $?))

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

        if [ "$storage/@inst@" -ef "$storage" ]; then
            "$instance" "$@" || rc=$?
        else
            msg '< external storage "%s" not initialized\n' "$storage" || rc=$?
        fi

        return $rc
    }

    if [ -n "${_keeper_oneshot+x}" ]; then
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
storage='@storage@'

pat='@glob@'
age='@days@'

msg0 '* Establish source and destination directories\n'

t="$(cd -L "$target" 2>/dev/null && echo "$PWD")" && target="$t" ||
    fatal '< cannot cd to target directory "%s"\n' "$target"
t="$(cd -L "$storage" 2>/dev/null && echo "$PWD")" && storage="$t" ||
    fatal '< cannot cd to storage directory "%s"\n' "$storage"
unset t

# Two configurations supported
#   1) hardlinks: .. mounted filesystem with siblings
#                  +- $target  is not mountpoint
#                  +- $storage is not mountpoint
#   2) symlinks:  both $target and $storage are mountpoints

  if [ "$target/.." -ef "$storage/.." ] &&
    mountpoint -q "$storage/.." &&
  ! mountpoint -q "$target" &&
  ! mountpoint -q "$storage"
then
    msg0 '> using hardlinks for data organization\n'

    # For same filesystem hardlinking should be enough that
    # target and storage
    #   a) are sibling on same filesystem
    #   b) should be on mounted filesystem
    #   c) neither of siblings is mountpoint
    unset xdrive
else
    msg0 '> using symlinks for data organization\n'

    # For cross-filesystem symlinking at least target and
    # storage should be mountpoints
    mountpoint -q "$target" ||
        fatal '< target storage "%s" not mounted\n' "$target"
    mountpoint -q "$storage" ||
        fatal '< external storage "%s" not mounted\n' "$storage"
    xdrive='x'
fi

# See how we called
case "$prog_name" in
    'keeper')
        daemon keeper "$target" "$storage" "$pat" "$@" || exit
        ;;
    'reaper')
        daemon reaper "$target" "$storage" "$age" "$@" || exit
        ;;
    *)
        fatal 'Program expected to be called as "%s" or "%s", not "%s"\n' \
            'keeper' 'reaper' "$prog_name" \
            #
        ;;
esac

exit 0
