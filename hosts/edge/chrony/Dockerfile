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

RUN apt-get -qq --no-install-recommends --no-install-suggests install \
    chrony

# make sure we do not clash with host uid/gid's
RUN groupmod -g 65097 _chrony \
 && usermod -u 65097 -g _chrony _chrony \
 && if [ -d /run/chrony ]; then chown _chrony:_chrony /run/chrony; fi \
 && install -d -m 0750 -o _chrony -g _chrony /var/lib/chrony/dump \
 && chown _chrony:_chrony /var/lib/chrony \
 && chmod 0750 /var/lib/chrony

## Configure chrony

ARG host=edge

COPY chrony/ /tmp/chrony/

RUN install -m 0644 /tmp/chrony/$host/conf.d/local.conf \
     /etc/chrony/conf.d/ \
 && install -m 0644 /tmp/chrony/$host/sources.d/local.sources \
     /etc/chrony/sources.d/ \
 && install -m 0640 -g _chrony /tmp/chrony/$host/chrony.keys \
     /etc/chrony/ \
 && rm -rf /tmp/chrony/ \
 && sed -e '$ aDAEMON_OPTS="${DAEMON_OPTS:+$DAEMON_OPTS }-d -r"' \
        -i /etc/default/chrony \
 && sed -e '/\s\+--start\s\+/{' \
        -e '  s,\(\s\+--quiet\s\+\),\1--background --no-close ,' \
        -e '  b' \
        -e '}' \
        -e '/\s\+--stop\s\+/{' \
        -e '  s,\s\+--exec\s\+\S\+\s*$, --name $NAME,' \
        -e '  b' \
        -e '}' \
        -i /etc/init.d/chrony \
 && sed -e 's,^\(pool\|server\|peer\|log\|logdir\)\s\+,#\0,' \
        -i /etc/chrony/chrony.conf

## Install docker-entrypoint.sh

COPY docker-entrypoint.sh /

RUN sed -e 's,@user@,_chrony,g' \
        -e 's,@name@,chrony,g' \
        -e 's,@named@,chronyd,g' \
        -e "s,@proxy_stdio@,@proxy_stdio@,g" \
        -e "s,@proxy_syslog@,@proxy_syslog@,g" \
        -i /docker-entrypoint.sh

## Make container executable

CMD [ "/etc/init.d/chrony", "start" ]
ENTRYPOINT [ "/docker-entrypoint.sh" ]
