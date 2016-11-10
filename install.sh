# check if docker installed
docker -v >/dev/null 2>&1 || { echo >&2 "Docker required but it's not installed.  Aborting."; exit 1; }

domain=$1
if [[  -z  $1  ]]; then
  read -p "Enter domain name of the host: " domain
fi
echo Domain=$domain

apt-get -y install nginx
#todo: check if file not exists
cat config/nginx-stage1.cfg | sed -e "s/{{domain}}/$domain/"  > /etc/nginx/sites-enabled/$domain
service nginx reload
echo $domain > /var/www/domain.txt
echo Checking domain...
sleep 1
response=$(curl -s $domain/domain.txt)
if [ "$domain" != "$response" ]; then
  echo "Domain check failed, check if DNS record exist!"
  exit 1
else
echo "...OK"
fi

echo Installing dehydrated  client
curl -s https://raw.githubusercontent.com/lukas2511/dehydrated/a13e41036381a76de1e77a6ddd3d30170d445d6d/dehydrated > /usr/local/bin/dehydrated
chmod +x /usr/local/bin/dehydrated

echo Generating ssl certificate
#staging url
mkdir /etc/dehydrated
mkdir /var/www/dehydrated
echo CA="https://acme-staging.api.letsencrypt.org/directory" > /etc/dehydrated/config
echo $domain > /etc/dehydrated/domains.txt
dehydrated -c
