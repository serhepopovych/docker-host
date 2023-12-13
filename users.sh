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

# Users storage
readonly users="$profiles_dir/_${inst-}/users"

readonly dflt_timezone='Europe/Kiev'
readonly dflt_organization='AcuCall'

# read profile 'guacamole'
read_profile_guacamole

# configure guacamole
gua_cfg_cb()
{
    (
        # Install default configuration file unless there is specific
        if [ ! -r "$users" ]; then
            t="$host_dir/_/${users##*/}"
            [ -f "$t" ] || exit

            rm -f "$users" ||:
            install -D -m 0600 -o root -g root "$t" "$users"
        fi

        # Source in subshell to not pollute environment
        eval $(
            {
                readonly v_pat='[a-z][-a-z0-9_]*'
                readonly q="[\"']\?"

                sed "$users" \
                    -n \
                    -e "s,^username_\([0-9]\+\)=${q}\(${v_pat}\)${q}$,\1 \2,p" \
                    #
            } | {
                [ -r "$users" ] && . "$users" >/dev/null || exit

                u=0

                while read -r id _; do
                    u=$((u += 1))
                    eval printf "\"%s='%s';\n\""                              \
                        '"username_${u}"'     "\"\${username_${id}-}\""       \
                        '"email_${u}"'        "\"\${email_${id}-}\""          \
                        '"fullname_${u}"'     "\"\${fullname_${id}-}\""       \
                        '"group_${u}"'        "\"\${group_${id}-}\""          \
                        '"timezone_${u}"'                                     \
                            "\"\${timezone_${id}:-\$dflt_timezone}\""         \
                        '"organization_${u}"'                                 \
                            "\"\${organization_${id}:-\$dflt_organization}\"" \
                        #
                done

                printf '%s;\n' "nr_users='$u'"
            }
        )
        [ "${nr_users:-0}" -gt 0 ] 2>/dev/null || exit

        echo
        h='* Adding users to guacamole ...'

        u=0
        while [ $((u += 1)) -le $nr_users ]; do
            eval "
                username=\"\${username_${u}-}\"
                email=\"\${email_${u}-}\"
                fullname=\"\${fullname_${u}-}\"
                group=\"\${group_${u}-}\"
                timezone=\"\${timezone_${u}-}\"
                organization=\"\${organization_${u}-}\"
            "
            [ -n "$username" ] || continue
            password="$(pwmake)"

            # Add or modify users
            gua_api 'UPDATE' "users/$username" >/dev/null <<EOF
{
  "username": "$username",
  "password": "$password",
  "attributes": {
    ${email:+\"guac-email-address\": \"$email\",}
    ${fullname:+\"guac-full-name\": \"$fullname\",}
    "timezone": "$timezone",
    "guac-organization": "$organization"
  }
}
EOF
            # Assign to group
            [ -z "$group" ] ||
            gua_api 'PATCH' "users/$username/userGroups" <<EOF
[
  {
    "op": "add",
    "path": "/",
    "value": "$group"
  }
]
EOF
            echo -n "$h $username"
            h=','

            # Store user
            [ $u -gt 1 ] ||
            printf  >"$users" '%s' "\
# DO NOT MODIFY. THIS FILE GENERATED AUTOMATICALLY BY
# SCRIPT AND COULD BE OVERWRITTEN ON IT'S NEXT RUN.
"
            printf >>"$users" '%s' "
# $username
username_$u='$username'
password_$u='$password'
email_$u='$email'
fullname_$u='$fullname'
group_$u='$group'
timezone_$u='$timezone'
organization_$u='$organization'
"
        done

        echo -n '. Done.'
    ) || return
}
guacamole_config
