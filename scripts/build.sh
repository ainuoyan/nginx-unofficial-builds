#!/bin/sh
set -eu
apk add --no-cache build-base linux-headers openssl-dev openssl-libs-static pcre2-dev pcre2-static zlib-dev zlib-static curl
version=$1
arch=$(uname -m)
name=nginx-$version-linux-$arch
cd "$(mktemp -d)"
curl -fsSLO --retry 3 "https://nginx.org/download/nginx-$version.tar.gz"
tar xzf "nginx-$version.tar.gz"
cd "nginx-$version"
./configure --group=nogroup --with-ld-opt=-static --with-http_realip_module --with-http_ssl_module --with-http_v2_module --with-stream --with-stream_ssl_module --with-threads
make -j"$(nproc)"
make install DESTDIR="$PWD/stage"
mv stage/usr/local/nginx "$name"
cp /packaging/* "$name/"
printf '%s\n' "$arch" > "$name/ARCH"
cp LICENSE "$name/"
strip "$name/sbin/nginx"
if readelf -l "$name/sbin/nginx" | grep -q INTERP; then exit 1; fi
tar czf "/out/$name.tar.gz" "$name"
mkdir -p /usr/local/nginx
tar xzf "/out/$name.tar.gz" -C /usr/local/nginx --strip-components=1
cd /usr/local/nginx
sed -i 's/listen       80;/listen       127.0.0.1:8080;/' conf/nginx.conf
sed -i '/^http {/a\    real_ip_header X-Forwarded-For;' conf/nginx.conf
grep -Fq 'real_ip_header X-Forwarded-For;' conf/nginx.conf
./sbin/nginx -t
./sbin/nginx
curl -fsS http://127.0.0.1:8080/ | grep -q 'Welcome to nginx'
./sbin/nginx -s quit
