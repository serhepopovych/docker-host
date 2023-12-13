# Set non-X11 login shell session auto-logout after timeout
if [ -z "${DISPLAY-}" ]; then
    readonly TMOUT=$((15 * 60)) 2>/dev/null
    export TMOUT
fi
