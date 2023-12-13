ARG UBUNTU_TAG=jammy
FROM ubuntu:$UBUNTU_TAG

## Update packages in upstream layer if any

RUN apt-get -qq update \
    && apt-get -qq dist-upgrade \
    && apt-get -qq --no-install-recommends --no-install-suggests install \
       apt-utils ca-certificates tzdata wget curl gnupg rsync netcat telnet \
       iproute2 net-tools mtr-tiny iputils-ping iputils-tracepath \
       lsof htop mc screen vim-tiny nano less \
       openssh-server

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

## Install nodejs & pm2

ARG NODE_MAJOR=18

RUN K=/etc/apt/keyrings && H=https://deb.nodesource.com \
 && install -d  "$K" \
 && curl -fsSL $H/gpgkey/nodesource-repo.gpg.key | \
    gpg --dearmor -o $K/nodesource.gpg \
 && echo "deb [signed-by=$K/nodesource.gpg] $H/node_$NODE_MAJOR.x nodistro main" | \
    tee /etc/apt/sources.list.d/nodesource.list \
 && apt-get -qq update \
 && apt-get -qq install nodejs

RUN npm install pm2 -g
RUN pm2 install pm2-logrotate && pm2 kill

## Install docker-entrypoint.sh and ecosystem.config.js.templ

COPY docker-entrypoint.sh /

WORKDIR /root
COPY ecosystem.config.js ./

## Configure openssh

ARG ip=192.0.2.244
ARG data_dir=/data/.

COPY openssh/sshd_config.d/sftp.conf \
     /etc/ssh/sshd_config.d/

RUN H=/etc/ssh/ \
 && sed -e "s,@ip@,$ip,g" \
        -e "s,@data_dir@,${data_dir%/*},g" \
        -i "${H}sshd_config.d/sftp.conf" \
 && find "$H" -name 'ssh_host_*_key*' -a -type f -a -delete \
 && for t in rsa ecdsa ed25519; do \
      t="hostkeys${H}ssh_host_${t}_key" && \
      ln -sf "$t"     "$H" && \
      ln -sf "$t.pub" "$H"; \
    done \
 && install -d /run/sshd

COPY openssh/mc.ini \
     openssh/screenrc \
     /tmp/

RUN make_skel() { \
      local H="$1" \
   && install -D -m 0644 /tmp/mc.ini "$H/.config/mc/ini" \
   && install -D -m 0644 /tmp/screenrc "$H/.screenrc" \
   && install -d "$H/.local/share" "$H/.local/bin" "$H/.cache" \
   && install -d -m 0700 "$H/.ssh" "$H/tmp" \
   && ln -sf '.local/bin' "$H/bin" || return; \
    } \
 && make_skel /root \
 && make_skel /etc/skel \
 && rm -f /tmp/mc.ini /tmp/screenrc

ARG user_name=exchange
# No login by default
ARG crypt_user_passwd=*

RUN install -d -m 0777 \
    "$data_dir/Archive" \
    "$data_dir/Errors" \
    "$data_dir/Reports" \
    "$data_dir/Payments" \
    "$data_dir/ListUpload" \
    "$data_dir/Prompts" \
 && useradd -G users \
            -s /usr/sbin/nologin \
            -p "$crypt_user_passwd" -m "$user_name"

## Make container executable

ENTRYPOINT [ "/docker-entrypoint.sh" ]
