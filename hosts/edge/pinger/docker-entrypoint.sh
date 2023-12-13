#!/bin/sh -e

if [ -n "${PID+x}" ]; then
    readonly timeout=$((24*60*60)) # 86400

    # watch for process
    while kill -0 "$PID"
    do
        sleep $timeout
    done
else
    PID=$$ exec gosu '@user@' "$0"
fi
