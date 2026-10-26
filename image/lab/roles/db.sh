# PostgreSQL 15 with a host firewall.
PG=/etc/postgresql/15/main
sed -i "s/^#\?listen_addresses.*/listen_addresses = '*'/" $PG/postgresql.conf
cp /lab/conf/pg_hba.conf $PG/pg_hba.conf
chown postgres:postgres $PG/pg_hba.conf
cp /lab/conf/db-host.nft /etc/nftables.conf
nft -f /etc/nftables.conf
echo postgres > /etc/lab-services
svc start postgres
