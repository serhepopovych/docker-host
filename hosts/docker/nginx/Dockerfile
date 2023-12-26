ARG NGINX_TAG=latest
FROM nginx:$NGINX_TAG

## Update packages in upstream layer if any

RUN apt-get -qq update \
    && apt-get -qq dist-upgrade \
    && apt-get -qq --no-install-recommends --no-install-suggests install \
       apt-utils vim-tiny less tzdata curl gnupg sudo

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

## Install certbotsh

ARG cbtsh_http_url=https://acme-le.gw.api.example.com/~letsencrypt
ARG cbtsh_http_auth=<changeme>
ARG cbtsh_domain=example.com
ARG cbtsh_ph=<passphrase>

COPY certbotsh/app/certbot.sh \
     certbotsh/sudoers.d/nginx \
     certbotsh/update.cfg \
    /tmp/

RUN /tmp/certbot.sh install client \
 && cbtsh_ph="$(printf '%s\n' "$cbtsh_ph" | sed -e 's,[\&],\\&,g')" \
 && install -m 0640 /tmp/nginx /etc/sudoers.d \
 && sed -e "s,@cbtsh_http_url@,$cbtsh_http_url,g" \
        -e "s,@cbtsh_domain@,$cbtsh_domain,g" \
        -e "s\"@cbtsh_ph@\"$cbtsh_ph\"g" \
        /tmp/update.cfg \
        >>/var/lib/letsencrypt/.config/letsencrypt/update.cfg \
 && sed -e 's,^#,,' \
        -e "s\"<changeme>\"$cbtsh_http_auth\"" \
        -i /var/lib/letsencrypt/.curlrc \
        -i /var/lib/letsencrypt/.wgetrc \
 && rm -f /tmp/certbot.sh \
          /tmp/nginx \
          /tmp/update.cfg

## Configure nginx

ARG data_dir='/data'

# !!! Make sure to provide exact hostname for production builds !!!
ARG ngx_hostname=[^.]+

# phpmyadmin
ARG pma_ip=192.0.2.210
# guac-guacamole
ARG gua_ip=192.0.2.222
# edge
ARG edge_ip=192.0.2.1
# dns
ARG dns_ip=8.8.8.8

COPY nginx/conf.d/*.conf /etc/nginx/conf.d/
COPY nginx/inc.d/*.inc /etc/nginx/inc.d/
COPY nginx/root/* $data_dir/root/
COPY nginx/app/nginx.sh /usr/sbin/

RUN ln -sf '/dev/stderr.nginx' '/var/log/nginx/error.log' \
 && ln -sf '/dev/stdout.nginx' '/var/log/nginx/access.log' \
 && sed -e "s,@user@,nginx,g" \
        -e "s,@proxy_stdio@,1,g" \
        -i /usr/sbin/nginx.sh \
 && for t in 'conf' 'inc'; do \
        find "/etc/nginx/$t.d/" -name "*.$t" -type f -a -execdir \
            sed -e "s,@ngx_hostname@,$ngx_hostname,g" \
                -e "s,@cbtsh_domain@,$cbtsh_domain,g" \
                -e "s,@pma_ip@,$pma_ip,g" \
                -e "s,@gua_ip@,$gua_ip,g" \
                -e "s,@edge_ip@,$edge_ip,g" \
                -e "s,@dns_ip@,$dns_ip,g" \
                -e "s,@data_dir@,$data_dir,g" \
                -i {} \+; \
    done \
 && ln -sfr /var/cache/nginx/dh2048.pem /etc/nginx/dh2048.pem

## Install docker-entrypoint.sh and ecosystem.config.js.templ

COPY docker-entrypoint.sh /

WORKDIR /root
COPY ecosystem.config.js.templ ./

## Make container executable

ENTRYPOINT [ "/docker-entrypoint.sh" ]
