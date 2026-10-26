# nginx (reverse proxy) -> python app on 127.0.0.1:8080 -> postgres on db1
MYIP=$(ip -4 -o addr show dev eth1 | awk '{print $4}' | cut -d/ -f1)
sed "s/__MYIP__/$MYIP/" /lab/conf/nginx-site.conf > /etc/nginx/sites-enabled/default
printf 'app\nnginx\n' > /etc/lab-services
svc start app
svc start nginx
