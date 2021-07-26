FROM python:3.9.6-slim-buster@sha256:5f8d3734d4b4016391ebc0162526b8335f2c16acc423d8424c1582c73a8bb053 AS base

# github metadata
LABEL org.opencontainers.image.source=https://github.com/uwcip/infrastructure-certbot

FROM base AS builder

# install python dependencies
COPY requirements.txt /
RUN python3 -m venv --system-site-packages /opt/certbot && \
    . /opt/certbot/bin/activate && \
    pip3 install --no-cache-dir -r /requirements.txt

FROM base AS final

# packages needed to run this thing
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get -q update && \
    apt-get install -y --no-install-recommends tini openssh-client rsync socat && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# copy the virtual environment that we just built
COPY --from=builder /opt /opt

# this script is for integrating with acme-dns
COPY acme-dns /usr/local/bin/acme-dns
RUN chmod +x /usr/local/bin/acme-dns

# copy the script for interacting with certbot
COPY certbot /usr/local/bin/certbot
RUN chmod +x /usr/local/bin/certbot

# install the entrypoint last to help with caching
COPY renew /usr/local/bin/renew
RUN chmod +x /usr/local/bin/renew

VOLUME ["/etc/letsencrypt", "/var/log/letsencrypt"]
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/renew"]
