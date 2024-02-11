#!/bin/sh -ue

# Requires: nc.openbsd(1), gawk(1), chroot(1), sleep(1), mkfifo(1), cat(1)
#           chown(1), rm(1)

# Usage: sleepx <secs> [<cb> [<args>...]]
sleepx()
{
    local secs=''
    [ "${1-}" -ge 0 ] 2>/dev/null ||
        "${secs:?missing or not a number 1st arg to sleepx() <secs>}"
    secs="$1"

    local cb="${2-}"
    cb="${cb#:}"
    [ $# -lt 2 ] || shift 2

    # This is bash(1) specific, readonly, variable (array)
    local in_bash="${BASH_VERSINFO+yes}"

    if [ -z "$cb" -a -n "${in_bash}" ]; then
        read -t $secs ||:
    else
        cb="${cb:-:}"

        while "$cb" "$@"; do
            # This spawns new process in this script interpreter
            # process group. Obviously this is suboptimal solution
            # as there might be a race with kill(1) that would end
            # sleep(1) before timeout reached.
            sleep 1 &

            # interruptible by signal
            while :; do
                # interruptible by signals
                wait $! || [ $? -le 128 ] || continue
                break
            done

            [ $((secs -= 1)) -gt 0 ] || break
        done
    fi
}

# Usage: syslog_cat {</path/to/socket1> ...|<SEP/path/to/socket1SEP...>}
syslog_cat()
{
    local sockets="${1:?missing 1st arg to syslog_cat() <sock>}"
    local ifs

    if [ -z "${sockets##[!/[:alnum:]_~-. ]/*}" ]; then
        ifs="$IFS"
        IFS="${sockets%%/*}"
        set -- $sockets
        IFS="$ifs"
    fi

    ifs='
'
    sockets="${ifs}/dev/log${ifs}"
    while [ $# -gt 0 ]; do
        # not empty, not ending with / (directory), absolute path
        if [ -n "${1%/}" -a -z "${1##/*}" ]; then
            # get rid of duplicates
            if [ -n "${sockets##${ifs}$1${ifs}}" ]; then
                sockets="$sockets$1$ifs"
            fi
        fi
        shift
    done

    {
        # no need to place each job into separate process group here:
        # subshell is a part of pipeline in parent process group
        set +m

        printf -- '<45>syslog_cat: syslog proxy v0.1' "$0"

        t=''
        for sock in $sockets; do
            # remove previous entry, if any
            rm -f "$sock" ||:

            # Note that OpenBSD's version of nc(1) seems only among other
            # alternatives has support for unbound UNIX datagram socket.
            # See nc.openbsd(1) for options -k, -U and -u.
            #
            # While socat(1) has such support with UNIX-RECV address type
            # we choose not to add such powerful tool to containers for
            # security reasons.
            nc.openbsd -dkluU "$sock" 2>/dev/null &

            # Usage: cb ...
            cb()
            {
                local sock="$1"
                [ ! -S "$sock" ] || return
            }
            sleepx 5 cb "$sock"

            if ! cb "$sock"; then
                # fix permissions
                chmod 0666 "$sock" ||:
                # report listening socket is ready
                printf -- '<46>syslog_cat: listening on %s' "$sock"
                t="$t$sock "
            fi
        done

        if [ -n "$t" ]; then
            # trick is to make gawk(1) read previous record: put new one
            printf -- '<192> '
        else
            printf -- '<40>syslog_cat: no listening sockets<192> '
            exit 125
        fi

        while ! wait; do
            :
        done
    } | {
        # spawned in subshell which is substituded with exec(1):
        # due to code being enclosed into {} group to make it more readable

        local prog
        if [ -n "${syslog_cat__strip_pri+x}" ]; then
            prog='{ if ($0 !~ "^\\s*$") { print $0; }; }'
        else
            prog='{ if ($0 !~ "^\\s*$") { print PRI$0; }; PRI=RT; }'
        fi

        exec chroot --userspec='nobody:nogroup' / \
             gawk -v RS='<[0-9]{1,3}>' "$prog" \
             >&${syslog_cat__fd:-2} 2>/dev/null
    } || return
}

# Usage: sig_handler__hook <signal> ...
sig_handler__hook()
{
    local signal="${1:?missing 1st arg to sig_handler__hook() <signal>}"
    shift

    case "$signal" in
        'EXIT')
            # Usage: sig_handler__hook EXIT
            exit $sig_handler__rc
            ;;
        'TERM')
            # Usage: sig_handler__hook TERM <-pid> <-job>...
            ;;
        'KILL')
            # Usage: sig_handler__hook KILL <-pid> <-job>...
            ;;
    esac

    return 0
}

# Usage: sig_handler_exit [<rc>]
sig_handler_exit()
{
    sig_handler__rc=${1:-$?}
    sig_handler 'EXIT'
}

# Usage: sig_handler <signal>
sig_handler()
{
    local signal="${1:?missing 1st arg to sig_handler() <signal>}"

    # Usage: sig_handler__fatal {rc|''} <msg> ...
    sig_handler__fatal()
    {
        local rc=${1:-$?}   && [ -n "${1+x}" ] && shift ||
            ${1:?missing 1st arg <rc>}
        local msg="${1-}" && [ -n "${1+x}" ] && shift ||:

        printf >&2 -- "%s: sig_handler(): $msg\n" \
            "$0" "$@" \
            #

        exit $rc
    }

    # Usage: sig_handler__jobs <pgroup> <job>...
    sig_handler__jobs()
    {
        local pgroup="${1:+-}"
        shift

        jobs=''
        while [ $# -gt 0 ]; do
            if [ -n "${1##*[!0-9]*}" ]; then
                jobs="${jobs:+$jobs }$pgroup$1"
            fi
            shift
        done
    }

    # Assert if job control isn't enabled which is default when non-interactive
    # since background jobs aren't on separate process groups and cannot be
    # terminated without also terminating this script interpreter process.
    case "$-" in
        *m*)
            ;;
        *)
            sig_handler__fatal 121 'job control is OFF'
            ;;
    esac

    case "$signal" in
        'EXIT')
            local pid='' jobs='' oneshot=''
            sig_handler__hook 'EXIT' ||:
            sig_handler__fatal 122 'should not return from sig_handler__hook()'
            ;;
    esac

    local jobs="${jobs-}"
    sig_handler__jobs '' $jobs

    local oneshot="${oneshot-}"

    local pid="${pid-}" pgrp=''
    if [ "${pid:-0}" -gt 0 ] 2>/dev/null; then
        pgrp="-$pid"
    else
        pid=''
    fi

    case "$signal" in
        'CHLD')
            # Our main and supplementary jobs running?
            local p
            for p in $pid $jobs ''; do
                kill -CONT $p 2>/dev/null || break
            done
            if [ -n "$p" ]; then
                # No, terminate remaining.
                signal='TERM'
            else
                # Yes, all fine. Either continued or signal not to our jobs.
                return 0
            fi
            ;;
    esac

    case "$signal" in
        'TERM'|'QUIT')
            # No reentrance
            trap '' 'TERM' 'QUIT' 'CHLD' 'EXIT'

            # Send only $signal to the main job process: process group, if any,
            # would be terminated in the same way as supplementary $jobs.
            local prev_rc rc=256
            while [ -n "$pid" ]; do
                # Main job process
                #   1) terminated before we kill(1) it: wait(1) has return code
                #   2) terminated normally           : rc <= 128
                #   3) terminated by signal          : rc = 128 + <signo> (x)
                #   4) wait(1) interrupted by signal : rc = 128 + <signo> (x)
                #   5) isn't our child process/job   : rc = 127
                kill -$signal $pid 2>/dev/null || [ $rc -ge 256 ] || break

                # wait(1) could be interrupted by signals received by
                # interpreter that further may decide that signal
                # ignored by the script (e.g. trap '' TERM);
                # interrupted wait(1) will return 128 + <signo> status
                while [ $rc -gt 128 ]; do
                    prev_rc=$rc
                    wait $pid && rc=0 || rc=$?
                    [ $rc -ne $prev_rc ] || break
                done
            done
            jobs="${oneshot:+$oneshot${jobs:+ }}$jobs"
            jobs="${jobs:-$pgrp}"

            local tries

            signal='TERM'
            tries=5

            while :; do
                # Before sending signal
                sig_handler__hook $signal $jobs ||:

                # We would send signals to process group lead first to give
                # it time to react and end it's child processes.
                #
                # After that we will send signals to entire process group to
                # terminate remaining process(es) in these groups.
                if ! kill -$signal $jobs 2>/dev/null; then
                    jobs=" $jobs "
                    if [ -n "${jobs##* $pgrp *}" ]; then
                        jobs="${jobs# }" && jobs="${jobs% }"
                    else
                        # Note that bash(1) does not call signal handlers set
                        # within signal handler (i.e. trap 'trap <code> <sig>'
                        # <sig> will not call <code> for second and further
                        # <sig>s): exit explicitly.
                        sig_handler_exit $rc
                    fi
                fi

                if [ -z "${jobs##*-*}" ]; then
                    if [  $((tries -= 1)) -gt 0 ]; then
                        sleepx 1
                    else
                        signal='KILL'
                        tries=5
                    fi
                else
                    # wait(1) will sleep until process group lead(s) finished,
                    # returning status of zero in that case, or interrupted by
                    # script trapped signal that interpretator receives,
                    # returning status of 128 + <signo>.
                    while ! wait; do
                        :
                    done

                    sig_handler__jobs '-' $pid $jobs
                fi
            done
            ;;
        'HUP'|'INT'|'USR1'|'USR2')
            # Send signal to main job process
            kill -$signal $pid 2>/dev/null ||:
            ;;
        *)
            sig_handler__fatal 123 'unsupported signal %s' "$signal"
            ;;
    esac
}

################################################################################

readonly \
    user='@user@' \
    name='@name@' \
    pidfile='/run/@name@/@named@.pid' \
    proxy_stdio='@proxy_stdio@' \
    proxy_syslog='@proxy_syslog@' \
    timeout=10 \
    #

# Turn on job control to put each job into separage process group
set -m

# Spawn child processes
trap 'sig_handler TERM' TERM
trap 'sig_handler INT' INT
trap 'sig_handler QUIT' QUIT
trap 'sig_handler HUP' HUP
trap 'sig_handler USR1' USR1
trap 'sig_handler USR2' USR2
trap 'sig_handler CHLD' CHLD

jobs=''

# Proxy stdandard output and error using named pipe to allow
# daemon to write to them after switching user (e.g. using gosu)
if [ -n "${proxy_stdio#\@proxy_stdio\@}" ]; then
    readonly \
        stdout='/dev/stdout' \
        stderr='/dev/stderr' \
        #

    # Remove original symlinks
    rm -f "$stdout" "$stderr"

    # Create named pipes group owned by user
    mkfifo -m 0660 "$stdout" "$stderr"
    chown ":$user" "$stdout" "$stderr"

    # Spawn cat(1) as input/output proxy
    cat "$stdout" &
    jobs="$jobs $!"
    cat "$stderr" >&2 &
    jobs="$jobs $!"

    # This serves two purposes:
    #  1) reopens file descriptors to point to named pipes making them
    #     available to child processes and via /proc/*/fd/*
    #  2) opens writers to avoid sending EOF after last writer exits
    #     (e.g. single echo >/dev/stdout will cause cat(1) exit)
    exec >"$stdout" 2>"$stderr"
fi

# Proxy syslog to either standard error or output file descriptor that
# either inherited or point to named pipe when proxifying standard I/O.
if [ -n "${proxy_syslog#\@proxy_syslog\@}" ]; then
    readonly \
        syslog="$proxy_syslog" \
        #

    syslog_cat__strip_pri='1' \
        syslog_cat "$syslog" &
    jobs="$jobs $!"
fi

# Remove stale pid file, if any
rm -f "$pidfile" ||:

# Run through SysV init script
/etc/init.d/$name start &
oneshot="$!"

pid=''

# Wait for pid file
secs=$timeout
while :; do
    if [ -s "$pidfile" ]; then
        read -r pid _ <"$pidfile" &&
            [ "$pid" -gt 0 ] 2>/dev/null || pid=''
        break
    else
        [ $((secs -= 1)) -ge 0 ] && sleep 1 || break
    fi
done

# Watch for main process
if [ -n "$pid" ]; then
    space="${oneshot:+ }"
    while kill -0 $pid; do
        sleep $timeout &

        oneshot="$oneshot$space$!"
        while :; do
            # interruptible by signals
            wait $! || [ $? -le 128 ] || continue
            break
        done
        oneshot="${oneshot%$space$!}"
    done
    unset space
fi

# Exit by sending TERM signal to self

# Usage: cb ...
cb()
{
    kill -TERM "$1" || return
}
sleepx $timeout cb $$

# Last restort
sig_handler_exit 124
