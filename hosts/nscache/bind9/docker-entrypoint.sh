#!/bin/sh

# Set option(s)
set -e
set -u
#set -x

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

# Usage: waitx <job> [<signal>]
waitx()
{
    local job="${1:?missing 1st arg to waitx() <job>}"
    local signal="${2:-CONT}"
    local rc

    # Signal handlers would interrupt wait(1) and run in it's caller context
    # (i.e. waitx() and it's callers) at least on dash(1).
    #
    # Make sure to NOT share local variable names that clash with globally used
    # by sig_handler() in waitx() and it's callers up to global level.
    #
    # Note that signal handler would see all local variables defined above and
    # by waitx(). Local may override global ones (e.g. local pid; getpid pid;
    # would override global pid=).

    until rc=0 && wait "$job"; do
        # wait(1) could be interrupted by signals received by interpreter that
        # further may decide that signal ignored by the script (e.g.
        # trap '' TERM); interrupted wait(1) will return 128 + <signo> status

        # Process
        #   1) terminated before we kill(1) it: wait(1) has return code
        #   2) terminated normally           : rc <= 128
        #   3) terminated by signal          : rc = 128 + <signo> (x)
        #   4) wait(1) interrupted by signal : rc = 128 + <signo> (x)
        #   5) isn't our child process/job   : rc = 127

        rc=$?
        if [ $rc -le 128 ]; then
            # not a 128 + <signo>: exited
            break
        elif kill -$signal "$job" 2>/dev/null; then
            # interrupted by signal
            continue
        else
            # not running, exit status >128
            break
        fi
    done

    return $rc
}

# Usage: pausefd
pausefd()
{
    # Usage: sleepfd
    sleepfd()
    {
        unset -f sleepfd

        local _
        while IFS=''; do
            # Consume all read(1) data from named pipe ignoring errors,
            # if any; NOT interruptible by signals (i.e. trap ... not run)
            read -r _ 2>/dev/null || [ $? -gt 128 ] || break
        done

        # Stop subshell/job only, until SIGCONT or SIGKILL. Stopping
        # $$ will also stop any signal processing by it.

        local p
        getpid p

        if [ "$p" -ne "$$" ]; then
            # To stop/kill send TERM followed by CONT to $pid
            while kill -STOP "$p"; do
                :
            done
        fi

        # If reached, exit with ENXIO, No such device or address
        exit 6
    }

    # Usage: rmfifo <fl>
    rmfifo()
    {
        unset -f rmfifo

        # File descriptor opened, can try to remove entry
        # from filesystem with unlink(2) ignoring errors.

        local fl="${1-}"
        [ ! -p "$fl" ] || rm -f "$fl" ||:
    }

    local p
    getpid p

    # Not using more secure mktemp(1) to avoid
    # external dependency on it
    local fl="/tmp/.sleepfd.$p"

    # Use restrictive permissions to minimize race
    mkfifo -m 0600 "$fl" || return

    if [ -n "${pausefd__stop-}" ]; then
        ## Uninterruptible by signals, never returns

        # See fifo(7) for read/write mode description
        if rmfifo "$fl"; then
            sleepfd
        fi <>"$fl"

        # Never reached
        exit
    else
        ## Interruptible by signals

        # Job control required
        assert_m 'pausefd'

        # See fifo(7) for read/write mode description
        sleepfd <>"$fl" &
        local sleepjob="$!"

        sh_oneshot_add "$sleepjob"

        # Block in open(2) until sleepfd() opens in read/write
        rmfifo "$fl" <"$fl"

        local rc=0
        waitx "$sleepjob" || rc=$?

        sh_oneshot_del "$sleepjob"

        return $rc
    fi
}

# Usage: pausex
pausex()
{
    local pausefd__stop=''
    pausefd || return
}

# Usage: stopx
stopx()
{
    local pausefd__stop='noreturn'
    pausefd
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
        pausex ||:
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

        local now t job

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

                sh_oneshot_add "$job"
                waitx "$job" ||:
                sh_oneshot_del "$job"
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
            # resuming in case they was stopped. Note that this signal
            # triggered for any child process, including external tools
            # and subshells, spawned by this script, so this might be
            # quite hotpoint even in case all code does is sleepx().
            #
            # Run through $pid and $jobs and resume all of them to ensure
            # they receive SIGTERM while running, instead of pending it.
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
        'USR2')
            printf >&2 'Jobs running by %u pid\n' "$$"
            jobs -l >&2
            return 0
            ;;
    esac

    case "$signal" in
        'TERM'|'QUIT')
            # No reentrance
            trap '' 'TERM' 'QUIT' 'CHLD' 'EXIT'

            local tries=3

            # Send $signal to the main process first, then try SIGTERM unless
            # $signal wasn't it initially. Otherwise terminate it in the same
            # way as supplementary $jobs.
            local rc=127 running
            while [ -n "$pid" ]; do
                running=''
                if kill -CONT $pid; then
                    # Process resumed, send signal
                    if kill -$signal $pid; then
                        running='yes'
                    fi
                fi 2>/dev/null

                # Do wait(1) if $pid is our child, resending signal
                waitx $pid $signal && rc=0 || rc=$?

                if [ $rc -ne 127 ]; then
                    # Valid return code, not running.
                    break
                else
                    [ -n "$running" ] || break

                    # Signal was sent, but child isn't our process/job and
                    # thus we can't track it's status with wait(1). Give it
                    # some time to handle signal and then retry.
                    if [ $((tries -= 1)) -gt 0 ]; then
                        sleepx 1
                    else
                        case "$signal" in
                            'TERM')
                                  # Still running, process like $jobs
                                  rc=127
                                  break
                                  ;;
                            *)
                                  signal='TERM'
                                  ;;
                        esac
                        tries=3
                    fi
                fi
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
            fi

            signal='TERM'
            tries=5

            while :; do
                # Before sending signal
                sig_handler__hook $signal $jobs ||:

                # Resume processes before sending signal
                kill -CONT $jobs 2>/dev/null ||:

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
        'HUP'|'INT'|'USR1')
            # Send signal to main job process
            kill -$signal $pid 2>/dev/null ||:
            ;;
        *)
            sig_handler__fatal 124 'unsupported signal %s' "$signal"
            ;;
    esac
}

# Usage: sh_oneshot_add <job>
sh_oneshot_add()
{
    local job="${1:?missing 1st arg to sh_oneshot_add() <job>}"

    if [ -n "${oneshot+x}" ]; then
        if [ -n "${oneshot##* $job *}" ]; then
            # Make visible to signal handler
            oneshot="${oneshot% } $job "
        fi
    fi
}

# Usage: sh_oneshot_del()
sh_oneshot_del()
{
    local job="${1:?missing 1st arg to sh_oneshot_del() <job>}"

    if [ -n "${oneshot+x}" ]; then
        if [ -z "${oneshot##* $job *}" ]; then
            # Hide from signal handler
            local t="${oneshot%% $job *}"
            oneshot="$t ${oneshot##* $job }"
            oneshot="${oneshot% }"
        fi
    fi
}

################################################################################

# Usage: main <argv0> <exe> ...
main()
{
    local prog_name="${0##*/}"
    shift

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

        # This would sleep uninterruptible to keep $stdout and $stderr
        # open in this subshell/job preventing cat(1) readers from exit.
        stopx
    }

    # Usage: start <exe> ...
    start()
    {
       run "$@" &
       runjob="$!"
    }
    local runjob=''

    if [ -n "${stdout-}" ]; then
        # Below output and error redirects affects only this `if' statement,
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
    jobs="$jobs$runjob "

    ## Main loop

    printf >&2 '%s: running as %u pid\n' "$prog_name" "$$"

    # Usage: cb ...
    cb()
    {
        local pidval
        if [ -s "$pidfile" ] && read -r pidval _ <"$pidfile" &&
           [ "$pidval" -gt 0 ] && kill -0 "$pidval"
        then
            pid="$pidval"
            return 1
        fi 2>/dev/null
    }
    sleepx $timeout cb

    if [ -n "$pid" ]; then
        waitx "$runjob" ||:
    fi

    ## Exit

    # Raise signal instead of calling "sig_handler 'TERM'"
    # as it could be intterupted with signal in the middle.

    # Usage: cb ...
    cb()
    {
        kill -TERM "$1" || return
    }
    sleepx $timeout cb $$

    # Last restort
    sig_handler_exit 125
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

    main "$0" "$@"
else
    # At least dash(1) job control (set -m) requires
    # to be attached to a controlling terminal (see tcgetpgrp(3).
    if [ ! -t 0 ]; then
        # bash(1) doesn't have such requirement:
        # have it as fallback
        exe='/bin/bash'
    fi

    # Pass arguments through a file and remove them from
    # our command line to look ps(1) output pretty.

    t="/tmp/.${0##*/}.$$"
    exec 4>"$t"
    rm -f "$t" || exit 125

    # Write arguments to file
    while [ $# -gt 0 ]; do
        printf -- '%s\n' "$1"
        shift
    done >&4

    # Use interpreter explicitly, not relying on shebang line
    # and fact that this file executable or can be executed.

    HIDE_ARGS='yes' exec "${exe:-/bin/sh}" "$0"
fi
