# BIND9, authoritative for dc.lab and the 10.x reverse zone.
cp /lab/conf/named.conf.options /etc/bind/named.conf.options
cp /lab/conf/named.conf.local /etc/bind/named.conf.local
cp /lab/conf/db.dc.lab /lab/conf/db.10 /etc/bind/
chown -R bind:bind /etc/bind
mkdir -p /var/log/named && chown bind:bind /var/log/named
echo named > /etc/lab-services
svc start named
