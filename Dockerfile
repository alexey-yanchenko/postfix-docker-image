FROM debian:buster-slim
MAINTAINER Luc Appelman "lucapppelman@gmail.com"

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
    && curl -fL -o /tmp/postfix.tar.gz http://cdn.postfix.johnriley.me/mirrors/postfix-release/official/postfix-3.5.8.tar.gz \
    #&& (echo "00e2b0974e59420cabfddc92597a99b42c8a8c9cd9a0c279c63ba6be9f40b15400f37dc16d0b1312130e72b5ba82b56fc7d579ee9ef975a957c0931b0401213c  /tmp/postfix.tar.gz" | sha512sum -c -) \
    && tar -xzf /tmp/postfix.tar.gz -C /tmp/ \
    && cd /tmp/postfix-* \
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
                    -subj "/CN=web-fuse.nl" \
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

# DKIM
# https://www.transip.nl/knowledgebase/artikel/3488-dkim-gebruiken-met-postfix/
RUN apt-get update && \
    apt -y install opendkim && \
    rm -rf /var/lib/apt/lists/* && \
    chown opendkim:opendkim /etc/opendkim/keys/ -R && \
    usermod -a -G opendkim postfix

#install procps for ps aux command
RUN apt-get update && apt-get install -y procps && rm -rf /var/lib/apt/lists/*

COPY rootfs /
COPY start.sh /start.sh

RUN chmod +x /etc/services.d/*/run \
            /etc/cont-init.d/* \
            /start.sh

EXPOSE 25 465 587

WORKDIR /etc/postfix

STOPSIGNAL SIGTERM

# should contain private.key and public.key RSA keys in PEM format
VOLUME /etc/ssl/dkim

#ENTRYPOINT ["/init"]

# start both postfix and opendkim
CMD ["/start.sh"]
