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
RUN groupadd -g 65099 bird \
 && useradd -u 65099 -g bird -d /run/bird -s /usr/sbin/nologin bird

RUN apt-get -qq --no-install-recommends --no-install-suggests install \
    bird2

## Configure bird

ARG host=none

COPY bird/ /tmp/bird/

RUN install -m 0640 -o bird -g bird /tmp/bird/$host/bird.conf /etc/bird/ \
 && rm -rf /tmp/bird/ \
 && sed -e '$ aBIRD_ARGS="${BIRD_ARGS:+$BIRD_ARGS }-P /run/bird/bird.pid -f"' \
        -i /etc/bird/envvars \
 && sed -e '/\s\+--start\s\+/{' \
        -e '  s,\(\s\+--quiet\s\+\),\1--background --no-close ,' \
        -e '  b' \
        -e '}' \
        -e '/\s\+--stop\s\+/{' \
        -e '  s,\s\+--exec\s\+\S\+\s*$,,' \
        -e '  b' \
        -e '}' \
        -i /etc/init.d/bird

## Install docker-entrypoint.sh

COPY docker-entrypoint.sh /

RUN sed -e "s,@user@,bird,g" \
        -e "s,@name@,bird,g" \
        -e "s,@named@,bird,g" \
        -e "s,@proxy_stdio@,@proxy_stdio@,g" \
        -e "s,@proxy_syslog@,@proxy_syslog@,g" \
        -i /docker-entrypoint.sh

## Make container executable

CMD [ "/etc/init.d/bird", "start" ]
ENTRYPOINT [ "/docker-entrypoint.sh" ]
