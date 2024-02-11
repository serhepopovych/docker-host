ARG UBUNTU_TAG=jammy
FROM ubuntu:$UBUNTU_TAG

## Update packages in upstream layer if any

RUN apt-get -qq update \
    && apt-get -qq dist-upgrade \
    && apt-get -qq --no-install-recommends --no-install-suggests install \
       apt-utils vim-tiny less ca-certificates tzdata locales gosu

## Configure timezone

ARG timezone=US/Eastern

RUN for timezone in "$timezone" 'US/Eastern' 'Etc/UTC'; do \
      tz="/usr/share/zoneinfo/$timezone" && \
      if [ -f "$tz" ]; then \
        echo "$timezone" >/etc/timezone && \
          ln -sf "$tz" /etc/localtime && \
        break; \
      fi; \
    done

## Configure locale

ARG locale=en_US.UTF-8

RUN sed -e "s,^#\s*\($locale\(\s\+.\+\)\?\)\s*$,\1,g" \
        -i /etc/locale.gen && \
    locale-gen && \
    update-locale "LANG=$locale"

## Install application

RUN apt-get -qq --no-install-recommends --no-install-suggests install \
    openssh-server netcat-openbsd gawk

## Configure openssh

ARG ip=192.0.2.244
ARG data_dir=/data/.

COPY openssh/sshd_config.d/sftp.conf \
     /etc/ssh/sshd_config.d/

VOLUME /etc/ssh/hostkeys

RUN H=/etc/ssh/ \
 && sed -e "s,@ip@,$ip,g" \
        -e "s,@data_dir@,${data_dir%/*},g" \
        -i "${H}sshd_config.d/sftp.conf" \
 && find "$H" -maxdepth 1 -a -name 'ssh_host_*_key*' -a -type f -a -delete \
 && for t in rsa ecdsa ed25519; do \
        t="hostkeys${H}ssh_host_${t}_key" && \
        ln -sf "$t"     "$H" && \
        ln -sf "$t.pub" "$H"; \
    done \
 && sed -e '/^check_config\(\)/{' \
        -e 'icheck_hostkeys() \{\' \
        -e '    local t="/etc/ssh/hostkeys/etc/ssh/ssh_host_rsa_key"\' \
        -e '    if [ ! -e "$t" ]; then\' \
        -e '        t="${t%/*}"\' \
        -e '        mkdir -p "$t"\' \
        -e '        t="${t%/etc/ssh}"\' \
        -e '        ssh-keygen -A -f "$t" ||:\' \
        -e '    fi\' \
        -e '\}\' \
        -e '' \
        -e '}' \
        -e 's,^\(\s\+\)\(check_privsep_dir\s*\)$,\1\2\n\1check_hostkeys\n,' \
        -i /etc/init.d/ssh \
 && ln -sf . /run/ssh \
 && sed -e '$ aSSHD_OPTS="${SSHD_OPTS:+$SSHD_OPTS }-D"' \
        -i /etc/default/ssh \
 && sed -e '/\s\+--start\s\+/{' \
        -e '  s,\(\s\+--quiet\s\+\),\1--background --no-close ,' \
        -e '  b' \
        -e '}' \
        -e '/\s\+--stop\s\+/{' \
        -e '  s,\s\+--exec\s\+\S\+\s*\(;\s*\),\1,' \
        -e '  b' \
        -e '}' \
        -i /etc/init.d/ssh

ARG user_name=exchange
# No login by default
ARG crypt_user_passwd=*

RUN useradd -G users \
      -s /usr/sbin/nologin \
      -p "$crypt_user_passwd" -m "$user_name" \
 && install -d -m 3711 \
      "$data_dir/dev" \
 && install -d -m 0777 \
      "$data_dir/Archive" \
      "$data_dir/Errors" \
      "$data_dir/Reports" \
      "$data_dir/Payments" \
      "$data_dir/ListUpload" \
      "$data_dir/Prompts"

## Install docker-entrypoint.sh

COPY docker-entrypoint.sh /

RUN sed -e "s,@user@,root,g" \
        -e "s,@name@,ssh,g" \
        -e "s,@named@,sshd,g" \
        -e "s,@proxy_stdio@,@proxy_stdio@,g" \
        -e "s,@proxy_syslog@,${data_dir%/*}/dev/log,g" \
        -i /docker-entrypoint.sh

## Make container executable

ENTRYPOINT [ "/docker-entrypoint.sh" ]
