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
    dns-root-data dnsmasq

# make sure we do not clash with host uid/gid's
RUN groupadd -g 65098 dnsmasq \
 && usermod -u 65098 -g dnsmasq dnsmasq \
 && if [ -d /run/dnsmasq ]; then chown dnsmasq:dnsmasq /run/dnsmasq; fi \
 && sed -e 's,nogroup,dnsmasq,g' \
        -i /etc/init.d/dnsmasq \
        -i /usr/lib/tmpfiles.d/dnsmasq.conf

## Configure dnsmasq

COPY dnsmasq/conf.d/local.conf \
     dnsmasq/conf.d/local.nftset \
     /etc/dnsmasq.d/
COPY dnsmasq/ethers.local \
     dnsmasq/hosts.local \
     /etc/

RUN sed -e 's,^#\?\(IGNORE_RESOLVCONF\)=.*$,\1=yes,' \
        -e '$ aDNSMASQ_OPTS="${DNSMASQ_OPTS:+$DNSMASQ_OPTS }-k -8 -"' \
        -i /etc/default/dnsmasq \
 && sed -e '/\s\+--start\s\+/{' \
        -e '  s,\(\s\+--quiet\s\+\),\1--background --no-close ,' \
        -e '  b' \
        -e '}' \
        -e '/\s\+--stop\s\+/{' \
        -e '  s,\s\+--exec\s\+\S\+\s*$, --name $NAME,' \
        -e '  b' \
        -e '}' \
        -e 's,^\(\s\+\${DNSMASQ_USER:+ -u \(\${DNSMASQ_USER}\)\)\(}\s*\\\s*\)$,\1 -g \2\3,' \
        -i /etc/init.d/dnsmasq

## Install docker-entrypoint.sh

COPY docker-entrypoint.sh /

RUN sed -e "s,@user@,dnsmasq,g" \
        -e "s,@name@,dnsmasq,g" \
        -e "s,@named@,dnsmasq,g" \
        -e "s,@proxy_stdio@,@proxy_stdio@,g" \
        -e "s,@proxy_syslog@,@proxy_syslog@,g" \
        -i /docker-entrypoint.sh

## Make container executable

ENTRYPOINT [ "/docker-entrypoint.sh" ]
