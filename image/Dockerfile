# One image for every node: think of it as the "golden VM image" of this DC.
# The ROLE env var (set in topology.clab.yml) decides which services start.
# Built locally, so it is native arm64 on Apple Silicon and amd64 elsewhere.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      # debugging toolbox (what you'd want on any real box)
      iproute2 iputils-ping iputils-arping iputils-tracepath traceroute mtr-tiny \
      tcpdump dnsutils curl netcat-openbsd socat nmap iperf3 ethtool \
      conntrack nftables strace lsof procps psmisc less vim-tiny jq ca-certificates \
      openssh-server \
      # services
      frr frr-pythontools bind9 nginx-light haproxy rsyslog \
      postgresql postgresql-client python3 python3-psycopg2 \
    && rm -rf /var/lib/apt/lists/*

# Database seeded at build time so every deploy starts from the same data.
RUN pg_ctlcluster 15 main start \
 && su postgres -c "psql -c \"CREATE ROLE app LOGIN PASSWORD 'app';\"" \
 && su postgres -c "createdb -O app shop" \
 && su postgres -c "psql -d shop -c \"CREATE TABLE orders(id serial primary key, item text, qty int); \
      INSERT INTO orders(item, qty) SELECT 'widget-'||g, (g % 7)+1 FROM generate_series(1,250) g; \
      ALTER TABLE orders OWNER TO app;\"" \
 && pg_ctlcluster 15 main stop

# sshd: key-only root login (the key is pushed by labctl after deploy)
RUN mkdir -p /root/.ssh /run/sshd && chmod 700 /root/.ssh \
 && printf 'PermitRootLogin prohibit-password\nPasswordAuthentication no\nUseDNS no\n' > /etc/ssh/sshd_config.d/lab.conf

# rsyslog: no kernel log inside containers
RUN sed -i '/imklog/s/^/#/' /etc/rsyslog.conf

COPY lab/ /lab/
RUN chmod +x /lab/entrypoint.sh /lab/bin/* /lab/roles/*.sh \
 && ln -s /lab/bin/svc /usr/local/bin/svc

ENTRYPOINT ["/lab/entrypoint.sh"]
