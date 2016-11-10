# check if docker installed
docker -v >/dev/null 2>&1 || { echo >&2 "Docker required but it's not installed.  Aborting."; exit 1; }
#docker-compose -v >/dev/null 2>&1 || { echo >&2 "docker-compose required but it's not installed.  Aborting."; exit 1; }
#todo: check docker and compose versions

domain=$1
if [[  -z  $1  ]]; then
  read -p "Enter domain name of the host: " domain
fi
echo Domain=$domain

#apt-get -y install nginx
#todo: check if file not exists
mkdir -p nginx/config
mkdir  nginx/www
cat config/nginx-stage1.cfg | sed -e "s/{{domain}}/$domain/"  > nginx/config/default.conf
docker run -p 80:80 -v $(pwd)/nginx/www:/var/www -v $(pwd)/nginx/config:/etc/nginx/conf.d -d --name nginx nginx
#service nginx reload

echo $domain > nginx/www/domain.txt
echo Checking domain...
sleep 1
response=$(curl -s $domain/domain.txt)
if [ "$domain" != "$response" ]; then
  echo "Domain check failed, check if DNS record exist!"
  exit 1
else
echo "...OK"
fi
exit 1

echo Installing dehydrated  client
curl -s https://raw.githubusercontent.com/lukas2511/dehydrated/a13e41036381a76de1e77a6ddd3d30170d445d6d/dehydrated > /usr/local/bin/dehydrated
chmod +x /usr/local/bin/dehydrated

echo Generating ssl certificate
mkdir /etc/dehydrated
mkdir /var/www/dehydrated
touch /etc/dehydrated/config
#staging url
#echo CA="https://acme-staging.api.letsencrypt.org/directory" > /etc/dehydrated/config
echo $domain > /etc/dehydrated/domains.txt
sleep 1
dehydrated -c

cat config/stage2/conf/nginx/default.conf | sed -e "s/{{domain}}/$domain/"  > /etc/nginx/sites-enabled/$domain
sleep 1
service nginx reload

cat config/stage2/conf/registry/config.yml.tmpl | sed -e "s/{{domain}}/$domain/" > config/stage2/conf/registry/config.yml
cat config/stage2/conf/registry-web/config.yml.tmpl | sed -e "s/{{domain}}/$domain/" > config/stage2/conf/registry-web/config.yml

cd config/stage2/
./generate-keys.sh
docker-compose up -d
