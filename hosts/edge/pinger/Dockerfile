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
       wget curl netcat-openbsd telnet \
       bind9-dnsutils dnstracer \
       iputils-ping iputils-tracepath \
       hping3 mtr-tiny traceroute tcptraceroute \
       iproute2 net-tools \
       screen

# make sure we do not clash with host uid/gid's
RUN groupadd -g 65096 pinger \
 && useradd -u 65096 -g pinger pinger

## Configure pinger

## Install docker-entrypoint.sh

COPY docker-entrypoint.sh /

RUN sed -e 's,@user@,pinger,g' \
        -i /docker-entrypoint.sh

## Make container executable

ENTRYPOINT [ "/docker-entrypoint.sh" ]
