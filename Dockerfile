FROM debian:buster-slim
LABEL Luc Appelman "lucapppelman@gmail.com"

RUN mkdir /tmp/postfix
COPY ./postfix /tmp/postfix
# Build and install Postfix
# https://git.launchpad.net/postfix/tree/debian/rules?id=94dfb9850484db5f47958eaa86f958857ab9834c
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends --no-install-suggests \
                inetutils-syslogd \
                ca-certificates \
    && update-ca-certificates \
    # Install Postfix dependencies
    && apt-get install -y --no-install-recommends --no-install-suggests \
                libpcre3 libicu63 \
                libdb5.3 libpq5 libmariadb3 libsqlite3-0 \
                libsasl2-2 \
                libldap-2.4 \
    # Install tools for building
    && toolDeps="curl make gcc g++ libc-dev" \
    && apt-get install -y --no-install-recommends --no-install-suggests $toolDeps \
    # Install Postfix build dependencies
    && buildDeps=" \
            libssl-dev \
            libpcre3-dev libicu-dev \
            libdb-dev libpq-dev libmariadbclient-dev libmariadb-dev-compat libsqlite3-dev libmariadb-dev-compat \
            libsasl2-dev \
            libldap2-dev \
            m4" \
    && apt-get install -y --no-install-recommends --no-install-suggests $buildDeps \
    # Download and prepare Postfix sources
    && cd /tmp/postfix \
    && sed -i -e "s:/usr/local/:/usr/:g" conf/master.cf \
    # Build Postfix from sources
    && make makefiles \
            CCARGS="-DHAS_SHL_LOAD -DUSE_TLS \
                    -DHAS_PCRE $(pcre-config --cflags) \
                    -DHAS_PGSQL -I/usr/include/postgresql \
                    -DHAS_MYSQL $(mysql_config --include) \
                    -DHAS_SQLITE -I/usr/include \
                    -DHAS_LDAP -I/usr/include \
                    -DUSE_CYRUS_SASL -I/usr/include/sasl \
                    -DUSE_SASL_AUTH -DDEF_SASL_SERVER=\\\"dovecot\\\" \
                    -DUSE_LDAP_SASL" \
            AUXLIBS="-lssl -lcrypto -lsasl2" \
            AUXLIBS_PCRE="$(pcre-config --libs)" \
            AUXLIBS_PGSQL="-lpq" \
            AUXLIBS_MYSQL="$(mysql_config --libs)" \
            AUXLIBS_SQLITE="-lsqlite3 -lpthread" \
            AUXLIBS_LDAP="-lldap -llber" \
            shared=yes \
            dynamicmaps=yes \
            pie=yes \
            daemon_directory=/usr/lib/postfix \
            shlibs_directory=/usr/lib/postfix \
            # No documentation included to keep image size smaller
            manpage_directory=/tmp/man \
            readme_directory=/tmp/readme \
            html_directory=/tmp/html \
    && make \
    # Create Postfix user and groups
    && addgroup --system --gid 91 postfix \
    && adduser --system --uid 90 --disabled-password \
                --no-create-home --home /var/spool/postfix \
                --ingroup postfix --gecos postfix \
                postfix \
    && adduser postfix mail \
    && addgroup --system --gid 93 postdrop \
    && adduser --system --uid 92 --disabled-password --shell /sbin/nologin \
                --no-create-home --home /var/mail/domains \
                --ingroup postdrop --gecos vmail \
                vmail \
    # Install Postfix
    && make upgrade \
    # Always execute these binaries under postdrop group
    && chmod g+s /usr/sbin/postdrop \
                /usr/sbin/postqueue \
    # Ensure spool dir has correct rights
    && install -d -o postfix -g postfix /var/spool/postfix \
    # Fix removed directories in default configuration
    && sed -i -e 's,^manpage_directory =.*,manpage_directory = /dev/null,' \
            -e 's,^readme_directory =.*,readme_directory = /dev/null,' \
            -e 's,^html_directory =.*,html_directory = /dev/null,' \
            /etc/postfix/main.cf \
    # Prepare directories for drop-in configuration files
    && install -d /etc/postfix/main.cf.d \
    && install -d /etc/postfix/master.cf.d \
    # Generate default TLS credentials
    && install -d /etc/ssl/postfix \
    && openssl req -new -x509 -nodes -days 365 \
                    -subj "/CN=mail.web-fuse.nl" \
                    -out /etc/ssl/postfix/public.key \
                    -keyout /etc/ssl/postfix/private.key \
    && chmod 0600 /etc/ssl/postfix/private.key \
    # Pregenerate Diffie-Hellman parameters (heavy operation)
    && openssl dhparam -out /etc/postfix/dh2048.pem 2048 \
    # Cleanup unnecessary stuff
    && apt-get purge -y --auto-remove \
                -o APT::AutoRemove::RecommendsImportant=false \
                $toolDeps $buildDeps \
    && rm -rf /var/lib/apt/lists/* \
            /etc/*/inetutils-syslogd \
            /tmp/*

# Install s6-overlay
RUN apt-get update \
    && apt-get install -y --no-install-recommends --no-install-suggests curl \
    && curl -fL -o /tmp/s6-overlay.tar.gz https://github.com/just-containers/s6-overlay/releases/download/v2.0.0.1/s6-overlay-amd64.tar.gz \
    && tar -xzf /tmp/s6-overlay.tar.gz -C / \
    # Cleanup unnecessary stuff
    && apt-get purge -y --auto-remove \
                -o APT::AutoRemove::RecommendsImportant=false \
                curl \
    && rm -rf /var/lib/apt/lists/* \
            /tmp/*

ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_CMD_WAIT_FOR_SERVICES=1

# create aliases file
RUN touch /etc/aliases && newaliases

COPY rootfs /

RUN chmod +x /etc/services.d/*/run \
            /etc/cont-init.d/*

EXPOSE 25 465 587

WORKDIR /etc/postfix

STOPSIGNAL SIGTERM

ENTRYPOINT ["/init"]

CMD ["/usr/lib/postfix/master", "-d"]
