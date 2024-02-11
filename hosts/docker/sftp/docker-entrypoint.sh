#!/bin/sh -ue

# Requires: nc.openbsd(1), gawk(1), chroot(1), sleep(1), mkfifo(1), cat(1)
#           chown(1), rm(1)

# Usage: assert_m [<func>]
assert_m()
{
    # Assert if job control isn't enabled which is default when non-interactive
    # since background jobs aren't on separate process groups and cannot be
    # terminated without also terminating this script interpreter process.
    case "$-" in
        *m*)
            ;;
        *)
            local m="${assert_m__ignore+yes}"
            local func="${1-}"

            : "${m:?${func:+$func: }job control is OFF}"
            ;;
    esac
}

# Usage: getpid <var>
getpid()
{
    local var="${1:?missing 1st arg to getpid() <var>}"

    # Use Linux specific /proc filesystem layout instead of $(exec sh ...)
    # to avoid subshell spawning and receiving yet another SIGCHLD that we
    # may care about with sig_handler().

    if cd -P '/proc/self'; then
        eval "$var='${PWD##*/}'"
        cd "$OLDPWD"
    fi
}

# Usage: mksleepfd
mksleepfd()
{
    local pid
    getpid pid

    # If running in job or subshell: can't use wait(1) on $sleepjob which is
    # needed to implement interruptible by signals infinite sleep (blocking)

    eval "sleepjob=\"\${sleepjob_$pid-}\""

    if [ -n "$sleepjob" ]; then
        if kill -0 "$sleepjob" 2>/dev/null; then
            return 0
        else
            unset -v sleepjob
            return 1
        fi
    fi

    # Usage: sleepfd_redirect_stdin
    sleepfd_redirect_stdin()
    {
        # Make sure $sleepjob is a valid number, no /, .. and . allowed

        local sleepjob="${sleepjob-}"
        sleepjob="${sleepjob##*[!0-9]*}"
        # Fallback to current process
        sleepjob="${sleepjob:-self}"

        # Note that on Linux /proc/$sleepjob/fd/0 points to deleted fifo
        # making possible for third-party processes with rights
        # to open it for read and/or write:
        #
        #     $ readlink /proc/$sleepjob/fd/0
        #     /tmp/.sleepfd.$pid (deleted)

        local sleepfl="/proc/$sleepjob/fd/0"

        # It must be named pipe
        [ -p "$sleepfl" ] || return

        # Do not reopen as current one might be opened in read/write mode.
        [ ! "$sleepfl" -ef "/proc/self/fd/0" ] || return 0

        exec <"$sleepfl" || return
    }

    # Usage: sleepfd
    sleepfd()
    {
        if sleepfd_redirect_stdin; then
            local _
            while IFS=''; do
                # Consume all read(1) data from named pipe ignoring errors,
                # if any; NOT interruptible by signals (i.e. trap ... not run)
                read -r _ 2>/dev/null || [ $? -gt 128 ] || break
            done
        else
            local sfd=''
            : "${sfd:?no file descriptor to sleep on, mksleepfd() first}"
        fi

        # If reached, exit with 128 + SIGPIPE to make it
        # look like read(1) from broken file descriptor.
        exit 141
    }

    # Usage: rmfifo <fl>
    rmfifo()
    {
        # File descriptor opened, can try to remove entry
        # from filesystem with unlink(2) ignoring errors.

        local fl="${1-}"
        [ ! -p "$fl" ] || rm -f "$fl" ||:
    }

    # Job control required
    assert_m 'mksleepfd'

    # Not using more secure mktemp(1) to avoid
    # external dependency on it
    local fl="/tmp/.sleepfd.$pid"

    # Use restrictive permissions to minimize race
    mkfifo -m 0600 "$fl" || return

    sleepfd <>"$fl" &
    eval "sleepjob_$pid=\"\$!\""

    if rmfifo "$fl"; then
        # Not polluting callers namespace
        unset -f rmfifo

        # Make sure $sleepjob is running or cleanup everything
        mksleepfd || return

        # Below standard input redirect affects only `if' statement on
        # return from which it will be restored to the original one.
        #
        # It will block in open(2) until sleepfd() opens in read/write.
    fi <"$fl"
}

# Usage: uptimex <var>
uptimex()
{
    local var="${1:?missing 1st arg to uptimex() <var>}"

    # This could be used to measure time intervals when
    # precision up to a second is enough, without
    # spawning subshell, that might have side effects in
    # some configurations (e.g. trigger SIGCHLD handler
    # on subshell exit).
    local _
    read $var _ <'/proc/uptime' || return
    eval "$var=\"\${$var%%.*}\""
}

# Usage: sleepx [inf|<secs> [<cb> [<args>...]]]
sleepx()
{
    # Do earlier because some time being spent while
    # processing commands until second `uptimex now'.
    local ts
    uptimex ts || return 0

    # Usage: sleep_inf
    sleep_inf()
    {
        while mksleepfd; do
            if wait "$sleepjob" 2>/dev/null; then
                # It is not expected that $sleepjob terminates,
                # especially with exit status 0
                break
            else
                # interrupted by signal?
                local rc=$?
                [ $rc -gt 128 ] || exit $rc
            fi
        done

        # Use same code as sleepfd()
        exit 141
    }

    # Usage: sleep_num <secs> [<cb> [<args>...]]
    sleep_num()
    {
        local secs="${1-}"

        local cb="${2-}"
        cb="${cb#:}"
        [ $# -lt 2 ] || shift 2

        local nr=1
        if [ -z "$cb" ]; then
            [ $secs -le 0 ] || nr=$secs
            cb=':'
        fi

        local now t rc job

        local space="${oneshot:+ }"
        while "$cb" "$@"; do
            [ $((secs -= nr)) -ge 0 ] || break

            t=$nr

            while uptimex now &&
                  t=$((t - (now - ts))) &&
                  ts=$now &&
                  [ $t -gt 0 ]
            do
                # timeout ins't reached
                sleep $t &
                job="$!"

                oneshot="${oneshot-}$space$job "
                while kill -0 "$job" 2>/dev/null; do
                    # interruptible by signals
                    wait "$job" || [ $? -le 128 ] || continue
                    break
                done
                oneshot="${oneshot%$space$job }"
            done
        done
    }

    # Job control required
    assert_m 'sleepx'

    local secs=''

    # See how we're called
    case "${1-}" in
        '')
            "${secs:?usage: sleepx [inf|<secs> [<cb> [<args>...]]}"
            ;;
        [Ii][Nn][Ff])
            [ $# -le 1 ] ||
            "${secs:?extra args after $1, usage: sleepx inf}"

            sleep_inf
            ;;
        *[!0-9]*)
            "${secs:?not a valid unsigned number of seconds to sleep}"
            ;;
        *)
            [ $1 -lt 2147483648 ] ||
            "${secs:?seconds to sleep should be less than 2147483648}"

            sleep_num "$@"
            ;;
    esac

    # Do not expose to the caller namespace
    unset -f sleep_inf sleep_num
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
        assert_m__ignore=1

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
    local func='sig_handler'

    local signal="${1:?missing 1st arg to $func() <signal>}"

    # Usage: sig_handler__fatal {rc|''} <msg> ...
    sig_handler__fatal()
    {
        local rc=${1:-$?} && [ -n "${1+x}" ] && shift ||
            ${1:?missing 1st arg <rc>}
        local msg="${1-}" && [ -n "${1+x}" ] && shift ||:

        printf >&2 -- "%s: $func(): $msg\n" \
            "$0" "$@" \
            #

        exit $rc
    }

    # Usage: sig_handler__jobs <pgroup> <job>...
    sig_handler__jobs()
    {
        local pgroup="${1:+-}"
        shift

        jobs=' '
        while [ $# -gt 0 ]; do
            if [ -n "${1##*[!0-9]*}" ]; then
                if [ -n "${jobs##* $1 *}" ]; then
                    jobs="$jobs$pgroup$1 "
                fi
            fi
            shift
        done

        # $jobs is either empty, or string that
        # begins and ends with single space
        jobs="${jobs# }" && jobs="${jobs:+ $jobs}"
    }

    # Job control required
    assert_m "$func"

    case "$signal" in
        'EXIT')
            local pid='' jobs='' oneshot=''
            sig_handler__hook 'EXIT' ||:
            sig_handler__fatal 122 'should not return from sig_handler__hook()'
            ;;
    esac

    local pid="${pid-}"
    [ "${pid:-0}" -gt 0 ] 2>/dev/null || pid=''

    local jobs="${jobs-}"
    sig_handler__jobs '' $jobs

    local oneshot="${oneshot-}"

    case "$signal" in
        'CHLD')
            # Make sure main process and jobs it depend on is running,
            # resuming in case they was suspend. Note that this signal
            # triggered for any child process, including external tools
            # and subshells, spawned by this script, so this might be
            # quite hotpoint even in case all code does is sleepx().
            #
            # Thus it is suggested to not to run any external tools or
            # subshells while waiting for main process, especially in
            # sleepx() helper that should not spawn processes at all.
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

                # Signal was sent, but child isn't our process/job and
                # cannot track it's status with wait(1), give some time
                # to main process to handle signal and exit.
                if [ $rc -eq 127 ]; then
                    sleepx 1
                    continue
                fi

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
            sig_handler__jobs '' $jobs $oneshot

            local pgrp
            if [ -n "$pid" ]; then
                pgrp="-$pid"
                jobs="${jobs:- $pgrp }"
            else
                # Pick first job from $jobs, if any
                pgrp="${jobs# }"
                pgrp="${pgrp%% *}"
                pgrp="${pgrp:+-$pgrp}"
                rc=123
            fi

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
                    if ! [ -n "${jobs##* $pgrp *}" ]; then
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
            sig_handler__fatal 124 'unsupported signal %s' "$signal"
            ;;
    esac
}

################################################################################

# Usage: main <exe> ...
main()
{
    local \
        user='@user@' \
        name='@name@' \
        pidfile='/run/@name@/@named@.pid' \
        proxy_stdio='@proxy_stdio@' \
        proxy_syslog='@proxy_syslog@' \
        timeout=10 \
        #

    # Turn on job control to put each job into separage process group
    set -m

    # Setup signal handlers early
    trap 'sig_handler TERM' TERM
    trap 'sig_handler INT' INT
    trap 'sig_handler QUIT' QUIT
    trap 'sig_handler HUP' HUP
    trap 'sig_handler USR1' USR1
    trap 'sig_handler USR2' USR2
    trap 'sig_handler CHLD' CHLD

    # Used by sig_handler()
    local \
        pid='' \
        jobs='' \
        oneshot='' \
        #

    # Make sleep file descriptor to named pipe and redirect input
    if mksleepfd; then
        jobs="$jobs$sleepjob "
        sleepfd_redirect_stdin
    fi

    # Proxy stdandard output and error using named pipe to allow
    # daemon to write to them after switching user (e.g. using gosu)
    if [ -n "${proxy_stdio#\@proxy_stdio\@}" ]; then
        local \
            stdout="/dev/stdout.$name" \
            stderr="/dev/stderr.$name" \
            #

        # Remove original symlinks
        rm -f "$stdout" "$stderr"

        # Create named pipes group owned by user
        mkfifo -m 0660 "$stdout" "$stderr"
        chown ":$user" "$stdout" "$stderr"

        # Spawn cat(1) as input/output proxy
        cat "$stdout" &
        jobs="$jobs$! "
        cat "$stderr" >&2 &
        jobs="$jobs$! "

        # Above readers will be blocked in open(2) until first writer (i.e.
        # file descriptor that opens named pipe in write-only or read/write
        # mode) comes.
    else
        local stdout='' stderr=''
    fi

    # Proxy syslog to either standard error or output file descriptor that
    # either inherited or point to named pipe when proxifying standard I/O.
    if [ -n "${proxy_syslog#\@proxy_syslog\@}" ]; then
        local \
            syslog="$proxy_syslog" \
            #

        # Usage: syslogd
        syslogd()
        {
            local syslog_cat__strip_pri='1'
            syslog_cat "$syslog"
        }

        syslogd &
        jobs="$jobs$! "
    else
        local syslog=''
    fi

    ## Remove stale pid file, if any

    rm -f "$pidfile" ||:

    ## Run application

    # Usage: run <exe> ...
    run()
    {
        local exe="${1:?missing 1st arg to run() <exe>}"
        shift

        "$exe" "$@" ||:

        # This would block indefinitely to keep $stdout and $stderr
        # open in this subshell, preventing cat(1) readers from exit.
        sleepfd
    }

    # Usage: start <exe> ...
    start()
    {
       run "$@" &
       jobs="$jobs$! "
    }

    if [ -n "${stdout-}" ]; then
       # Below output and error redirects affects only this `if' statement:
       # on return from which they will be restored to the original ones.
       #
       # This will wake up cat(1) readers, started by $proxy_stdio, right after
       # both input and output file descriptors opened in write-only mode.

        if :; then
            start "$@"
        fi >"$stdout" 2>"$stderr"
    else
        start "$@"
    fi

    ## Main loop

    # Usage: cb ...
    cb()
    {
        local pidval
        if [ -s "$pidfile" ] && read -r pidval _ <"$pidfile" &&
           [ "$pidval" -gt 0 ] 2>/dev/null && kill -0 "$pidval" 2>/dev/null
        then
            pid="$pidval"
            return 1
        fi
    }
    sleepx $timeout cb

    if [ -n "$pid" ]; then
        sleepx inf
    else
        sig_handler 'TERM'
    fi
}

if [ -n "${HIDE_ARGS+yes}" ]; then
    if :; then
        # Close write-only file descriptor right after file it
        # refers to was opened read-only as standard input for
        # this `if' statement
        exec 4>&-

        arg=''
        while IFS='' read -r arg; do
            set -- "$@" "${arg-}"
        done
        unset -v arg

        # Below will open file descriptor reference
        # as regular file in read-only mode at pos 0
    fi </dev/fd/4

    # Do not export to external commands
    # (but still to subshells)
    unset -v HIDE_ARGS

    main "$@"
else
    t="/tmp/.${0##*/}.$$"
    exec 4>"$t"
    rm -f "$t" || exit 125

    # Write arguments to file
    while [ $# -gt 0 ]; do
        printf -- '%s\n' "$1"
        shift
    done >&4

    HIDE_ARGS='yes' exec "$0"
fi
