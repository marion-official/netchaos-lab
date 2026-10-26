# A customer on the internet.
echo "203.0.113.10 shop.example.com" >> /etc/hosts
printf 'nameserver 203.0.113.53\n' > /etc/resolv.conf   # no public DNS in this lab; use /etc/hosts
: > /etc/lab-services
