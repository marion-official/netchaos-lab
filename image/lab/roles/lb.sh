# HAProxy in front of the web tier.
cp /lab/conf/haproxy.cfg /etc/haproxy/haproxy.cfg
cp /lab/conf/rsyslog-haproxy.conf /etc/rsyslog.d/49-haproxy.conf
svc restart rsyslog
echo haproxy > /etc/lab-services
svc start haproxy
