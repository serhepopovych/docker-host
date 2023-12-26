#!/bin/bash -ue

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

    # This is bash(1) specific, readonly, variable (array)
    local in_bash="${BASH_VERSINFO+yes}"

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

    # Usage: sig_handler__sleep1
    sig_handler__sleep1()
    {
        if [ -n "${in_bash}" ]; then
            read -t 1 ||:
        else
            # This spawns new process in this script interpreter
            # process group. Obviously this is suboptimal solution
            # as there might be a race with kill(1) that would end
            # sleep(1) before timeout reached.
            sleep 1 &
            while ! wait $!; do
                :
            done
        fi
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
                        sig_handler__sleep1
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
    proxy_stdio='@proxy_stdio@' \
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

# proxy stdandard output and error using named pipe to allow
# daemon to write to them after switching user (e.g. using gosu)
if [ -n "${proxy_stdio#\@proxy_stdio\@}" ]; then
    readonly \
        stdout='/dev/stdout.nginx' \
        stderr='/dev/stderr.nginx' \
        #

    # remove named pipes, if any
    rm -f "$stdout" "$stderr"

    # create named pipes group owned by user
    mkfifo -m 0660 "$stdout" "$stderr"
    chown ":$user" "$stdout" "$stderr"

    # spawn cat(1) as input/output proxy
    cat "$stdout" &
    jobs="$!"
    cat "$stderr" >&2 &
    jobs="$jobs $!"

    # this serves two purposes:
    #  1) reopens file descriptors to point to named pipes making them
    #     available to child processes and via /proc/*/fd/*
    #  2) opens writers to avoid sending EOF after last writer exits
    #     (e.g. single echo >/dev/stdout will cause cat(1) exit)
    exec >"$stdout" 2>"$stderr"
else
    jobs=''
fi

/usr/sbin/nginx "$@" &
pid="$!"

while ! wait; do
    :
done

sig_handler_exit 0
