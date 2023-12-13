#!/bin/sh -e

if [ -n "${PID+x}" ]; then
    readonly timeout=10

    # Usage: sleepx <timeout>
    sleepx()
    {
        [ -n "${secs-}" ] ||
            secs="${1:?missing 1st arg to sleepx() <timeout>}"

        if [ $((secs -= 1)) -ge 0 ]
        then
            sleep 1
        else
            exit 121
        fi
    }

    # wait for pid file
    unset secs

    while :; do
        if [ -s "$PID" ]; then
            if read -r PID _ <"$PID" &&
               [ -n "${PID##*[!0-9]*}" ]
            then
                break
            else
                exit
            fi
        else
            sleepx $timeout
        fi
    done

    # Usage: sig_handler <signal>
    sig_handler()
    {
        # not interrupting signal handler on pipeline error
        set +e

        # terminate sleep(1) job
        kill -TERM "$!"

        local signal="${1:?missing 1st arg to sig_handler() <signal>}"

        case "$signal" in
            'TERM'|'INT'|'QUIT')
                # no reentrance
                trap '' 'TERM' 'INT' 'QUIT'
                unset -f sig_handler

                # wait for process to exit
                unset secs

                while kill -$signal "$PID" 2>/dev/null
                do
                    sleepx $timeout
                done

                # now exit successfully
                exit 0
                ;;
            'HUP'|'USR1'|'USR2')
                # send signal to main $PID
                kill -$signal "$PID"
                ;;
            *)
                echo >&2 "$0: sig_handler(): unsupported signal \"$signal\""
                exit 120
                ;;
        esac
    }
    trap 'sig_handler TERM' TERM
    trap 'sig_handler INT' INT
    trap 'sig_handler QUIT' QUIT
    trap 'sig_handler HUP' HUP
    trap 'sig_handler USR1' USR1
    trap 'sig_handler USR2' USR2

    # watch for process
    while kill -0 "$PID"
    do
        sleep $timeout &
        # interruptible by signals
        wait
    done
else
    pid='/run/@name@/@named@.pid'

    # remove stale pid file, if any
    rm -f "$pid" ||:

    /etc/init.d/@name@ start || exit

    PID="$pid" exec gosu '@user@' "$0"
fi
