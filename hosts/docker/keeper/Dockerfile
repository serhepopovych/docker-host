ARG UBUNTU_TAG=jammy
FROM ubuntu:$UBUNTU_TAG

## Update packages in upstream layer if any

RUN apt-get -qq update \
    && apt-get -qq dist-upgrade \
    && apt-get -qq --no-install-recommends --no-install-suggests install \
       apt-utils ca-certificates tzdata curl gnupg lsof vim-tiny nano less

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

## Install application

RUN apt-get -qq --no-install-recommends --no-install-suggests install tmpreaper

ARG app_dir=/app

ARG target=/data/target
ARG storage=/data/storage

ARG inst
ARG glob='*.wav'
ARG days=1275

COPY keeper/app/keeper.sh $app_dir/

RUN sed -e "s,@target@,$target,g" \
        -e "s,@storage@,$storage,g" \
        -e "s,@inst@,$inst,g" \
        -e "s,@glob@,$glob,g" \
        -e "s,@days@,$days,g" \
        -i $app_dir/keeper.sh \
 && ln -sf keeper.sh $app_dir/reaper.sh

# Following will stop docker-run(1) with lchown() on .../_data (root)
# error to avoid running container with non-own target attached early.
RUN install -d "$target" && ln -sf . "$target/$inst"

## Install docker-entrypoint.sh and ecosystem.config.js.templ

COPY docker-entrypoint.sh /

WORKDIR /root
COPY ecosystem.config.js.templ ./

RUN sed -e "s,@app_dir@,$app_dir,g" \
        -i /docker-entrypoint.sh

## Make container executable

ENTRYPOINT [ "/docker-entrypoint.sh" ]
