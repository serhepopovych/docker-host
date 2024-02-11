ARG DEBIAN_TAG=bookworm
FROM debian:$DEBIAN_TAG

## Update packages in upstream layer if any

RUN apt-get -qq update \
    && apt-get -qq dist-upgrade \
    && apt-get -qq --no-install-recommends --no-install-suggests install \
       apt-utils vim-tiny less ca-certificates tzdata locales gosu

## Configure timezone

ARG timezone=Europe/Kiev

RUN for timezone in "$timezone" 'Europe/Kiev' 'Etc/UTC'; do \
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

# make sure we do not clash with host uid/gid's; remove dirs: init will recreate
RUN groupmod -g 65095 www-data \
 && usermod -u 65095 -g www-data www-data \
 && rm -rf /run/lighttpd /var/cache/lighttpd /var/log/lighttpd /var/www \
 && install -d -m 0755 /var/www/

RUN apt-get -qq --no-install-recommends --no-install-suggests install \
    lighttpd

## Configure lighttpd

ARG host=none

COPY lighttpd/ /tmp/lighttpd/

RUN install -m 0640 -o root -g www-data /tmp/lighttpd/$host/lighttpd.conf /etc/lighttpd/ \
 && install -m 0640 -o root -g www-data /tmp/lighttpd/www/index.html /var/www/index.html \
 && rm -rf /tmp/lighttpd/ \
 && sed -e '/\s\+--start\s\+/{' \
        -e '  s,\(\s\+--quiet\s\+\),\1--background --no-close ,' \
        -e '  b' \
        -e '}' \
        -e '/\s\+--stop\s\+/{' \
        -e '  n' \
        -e '  s,\s\+--exec\s\+\S\+\s*$, --name $NAME,' \
        -e '  b' \
        -e '}' \
        -e 's,^\(PIDFILE=/run\)\(/$NAME.pid\)$,\1/$NAME\2,' \
        -e 's,^\(DAEMON_OPTS="\)\(.*"\),\1-D \2,' \
        -i /etc/init.d/lighttpd

## Install docker-entrypoint.sh

COPY docker-entrypoint.sh /

RUN sed -e "s,@user@,www-data,g" \
        -e "s,@name@,lighttpd,g" \
        -e "s,@named@,lighttpd,g" \
        -e "s,@proxy_stdio@,1,g" \
        -e "s,@proxy_syslog@,@proxy_syslog@,g" \
        -i /docker-entrypoint.sh \
        -i /etc/lighttpd/lighttpd.conf

## Make container executable

CMD [ "/etc/init.d/lighttpd", "start" ]
ENTRYPOINT [ "/docker-entrypoint.sh" ]
