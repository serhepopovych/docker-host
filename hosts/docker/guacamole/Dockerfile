ARG GUACAMOLE_TAG=latest
FROM guacamole/guacamole:$GUACAMOLE_TAG

# Parent Dockerfile has been switched to unprivileged user
USER root

## Install docker-entrypoint.sh and ecosystem.config.js.templ

ARG LDAP_NETWORK_TIMEOUT=10

COPY docker-entrypoint.sh /

RUN sed -e "s,@ldap_network_timeout@,$LDAP_NETWORK_TIMEOUT,g" \
        -i /docker-entrypoint.sh

## Make container executable

USER guacamole

CMD []
ENTRYPOINT [ "/docker-entrypoint.sh" ]
