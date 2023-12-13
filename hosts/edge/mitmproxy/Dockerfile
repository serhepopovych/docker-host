ARG PYTHON_TAG=3-slim-bullseye
FROM python:$PYTHON_TAG

## Update packages in upstream layer if any

RUN apt-get -qq update \
    && apt-get -qq dist-upgrade \
    && apt-get -qq --no-install-recommends --no-install-suggests install \
       apt-utils vim-tiny less ca-certificates tzdata gosu

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

## Install application

ARG user=mitmproxy
ARG data_dir=/data

# If updating UID/GID make sure also to adjust firewall configuration
# for egress packets to exclude mitmproxy own traffic from redirect
RUN groupadd -g 65099 "$user" \
 && useradd -g 65099 -u 65099 -d "$data_dir" -s /bin/false -M "$user"

RUN pip install mitmproxy

## Configure mitmproxy

ARG oba_hostname=mitm.it
ARG listen_host=127.0.0.1
ARG listen_port=8080
ARG web_host=127.0.0.1
ARG web_port=8081

COPY mitmproxy/conf.d/config.yaml "$data_dir/.mitmproxy/"

RUN sed -e "s,@oba_hostname@,$oba_hostname,g" \
        -e "s,@listen_host@,$listen_host,g" \
        -e "s,@listen_port@,$listen_port,g" \
        -e "s,@web_host@,$web_host,g" \
        -e "s,@web_port@,$web_port,g" \
        -i "$data_dir/.mitmproxy/config.yaml"

## Install docker-entrypoint.sh

COPY docker-entrypoint.sh /

WORKDIR $data_dir

RUN sed -e "s,@user@,$user,g" \
        -i /docker-entrypoint.sh

## Make container executable

ENTRYPOINT [ "/docker-entrypoint.sh" ]
