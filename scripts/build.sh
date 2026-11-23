#!/bin/sh
set -eu
apk add --no-cache build-base linux-headers openssl-dev openssl-libs-static pcre2-dev zlib-dev zlib-static curl
version=$1
arch=$(uname -m)
name=nginx-$version-linux-$arch
cd "$(mktemp -d)"
curl -fsSLO --retry 3 "https://nginx.org/download/nginx-$version.tar.gz"
tar xzf "nginx-$version.tar.gz"
cd "nginx-$version"
./configure --prefix=/opt/nginx --with-ld-opt=-static --with-http_ssl_module --with-http_v2_module --with-stream --with-stream_ssl_module --with-threads
make -j"$(nproc)"
make install DESTDIR="$PWD/stage"
mv stage/opt/nginx "$name"
cp LICENSE "$name/"
strip "$name/sbin/nginx"
if readelf -l "$name/sbin/nginx" | grep -q INTERP; then exit 1; fi
tar czf "/out/$name.tar.gz" "$name"
mkdir test
cd test
tar xzf "/out/$name.tar.gz"
cd "$name"
sed -i 's/listen       80;/listen       127.0.0.1:8080;/' conf/nginx.conf
./sbin/nginx -p "$PWD/" -t
./sbin/nginx -p "$PWD/"
curl -fsS http://127.0.0.1:8080/ | grep -q 'Welcome to nginx'
./sbin/nginx -p "$PWD/" -s quit
