#!/usr/bin/env bash

	#font
	n=$(tput sgr0);
	bold=$(tput bold);

	#path
	way=$(cd "$(dirname "$0")"; pwd)
	source "$way/config"

# install docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt update
apt install -y apt-transport-https ca-certificates curl software-properties-common tree
apt install -y docker-ce docker-compose

systemctl start docker

#create cert
cert_dir="${way}/certs"
mkdir -p $cert_dir
#ca ssl
openssl genrsa -out ${cert_dir}/root.key 4096
openssl req -x509 -newkey rsa:4096 -passout pass:1234 -keyout ${cert_dir}/root.key -out ${cert_dir}/root.crt -subj "/C=UA/O=VM/CN=${HOST_NAME}ca" 
openssl genrsa -out ${cert_dir}/web.key 4096
openssl req -new -key ${cert_dir}/web.key -out ${cert_dir}/web.csr -subj "/C=UA/O=VM/CN=${HOST_NAME}" \
	 -reqexts SAN -config <(cat /etc/ssl/openssl.cnf <(printf "[SAN]\nsubjectAltName=DNS:${HOST_NAME},DNS:${EXTERNAL_IP}"))
openssl x509 -req -in ${cert_dir}/web.csr -CA ${cert_dir}/root.crt -passin pass:1234 -CAkey ${cert_dir}/root.key \
	-CAcreateserial -out ${cert_dir}/web.crt -days 365 -extfile <(printf "subjectAltName=DNS:${HOST_NAME},DNS:${EXTERNAL_IP}")
cat ${cert_dir}/root.crt >> ${cert_dir}/web.crt

#nginx conf
nginx_dir="${way}/etc"
mkdir -p $nginx_dir
cat << nginxconf > $nginx_dir/nginx.conf
server {
	listen 443 ssl;
	ssl on;
	ssl_certificate /etc/ssl/web.crt;
	ssl_certificate_key /etc/ssl/web.key;
	server_name ${HOST_NAME};
location / {
	proxy_pass http://apache/;
	}
	error_page 497 =444 @close;
	location @close {
			return 0;
			}
	}

nginxconf

#docker compose yml
mkdir -p $NGINX_LOG_DIR
cat << dockercompose > $way/docker-compose.yml
version: '2'
services:
  nginx:
    image: $NGINX_IMAGE
    ports:
      - '$NGINX_PORT:443'
    volumes:
      - ${nginx_dir}/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - ${cert_dir}:/etc/ssl:ro
      - ${NGINX_LOG_DIR}:/var/log/nginx
  apache:
    image: $APACHE_IMAGE

dockercompose

docker-compose up -d

tree

docker-compose ps

curl https://${EXTERNAL_IP}:${NGINX_PORT} --cacert ${cert_dir}/web.crt
