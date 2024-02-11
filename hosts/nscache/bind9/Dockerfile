ARG DEBIAN_TAG=bookworm
FROM debian:$DEBIAN_TAG

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

# make sure we do not clash with host uid/gid's
RUN groupadd -g 65098 bind \
 && useradd -u 65098 -g bind -d /var/cache/bind -s /usr/sbin/nologin bind

RUN apt-get -qq --no-install-recommends --no-install-suggests install \
    dns-root-data bind9 bind9-utils bind9-dnsutils bind9-host

## Configure bind9

ARG host=none

COPY bind9/ /tmp/bind9/

RUN install -m 0644 -g bind -t /etc/bind/ \
     /tmp/bind9/$host/named.conf.options \
     /tmp/bind9/$host/named.conf.local \
     /tmp/bind9/$host/named.conf.query-source \
     /tmp/bind9/$host/db.rpz \
 && rm -rf /tmp/bind9/ \
 && sed -e 's,^#\?\(RESOLVCONF\)=.*$,\1=no,' \
        -e '$ aOPTIONS="${OPTIONS:+$OPTIONS }-g"' \
        -i /etc/default/named \
 && sed -e '/\s\+--start\s\+/{' \
        -e '  s,\(\s\+--quiet\s\+\),\1--background --no-close ,' \
        -e '  b' \
        -e '}' \
        -e '/\s\+--stop\s\+/{' \
        -e '  s,\s\+--exec\s\+\S\+\s*$, --name $NAME,' \
        -e '  b' \
        -e '}' \
        -i /etc/init.d/named

## Install docker-entrypoint.sh

COPY docker-entrypoint.sh /

RUN sed -e "s,@user@,bind,g" \
        -e "s,@name@,named,g" \
        -e "s,@named@,named,g" \
        -e "s,@proxy_stdio@,@proxy_stdio@,g" \
        -e "s,@proxy_syslog@,@proxy_syslog@,g" \
        -i /docker-entrypoint.sh

## Make container executable

CMD [ "/etc/init.d/named", "start" ]
ENTRYPOINT [ "/docker-entrypoint.sh" ]
