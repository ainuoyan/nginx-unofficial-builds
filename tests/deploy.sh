#!/usr/bin/env bash
# Run only on a disposable GitHub-hosted Linux runner.
set -euo pipefail
prefix=/usr/local/nginx
unit=/etc/systemd/system/nginx.service
[[ ! -e $prefix && ! -e $unit && ! -L $unit ]]
tmp=$(mktemp -d)
tar -xf "$1" -C "$tmp"
cd "$tmp"/nginx-*-linux-*
reject() { if "$@"; then echo "unexpected success: $*" >&2; exit 1; fi; }
for script in install update uninstall; do
    "./$script.sh" --lang zh --help | grep -q '用法'
    "./$script.sh" --lang en --help | grep -q Usage
done
# Use the distribution defaults, with a private test listener.
sed -i 's/listen       80;/listen       127.0.0.1:18880;/' conf/nginx.conf
sed -i '/^http {/a\    real_ip_header X-Forwarded-For;' conf/nginx.conf
./install.sh --lang zh
systemctl is-enabled nginx.service
curl -fsS http://127.0.0.1:18880/ | grep -q 'Welcome to nginx'
systemctl reload nginx.service
echo preserved > "$prefix/html/site"
echo certificate-fixture > "$prefix/conf/site.crt"
sha256sum "$prefix"/{conf/nginx.conf,conf/site.crt,html/site} > "$tmp/keep"
oldpid=$(systemctl show -p MainPID --value nginx)
./update.sh
[[ $(systemctl show -p MainPID --value nginx) == "$oldpid" ]]
# ELF tolerates trailing bytes. Exercise a same-version/different-digest update.
printf '\0' >> sbin/nginx
echo 'invalid_directive;' >> "$prefix/conf/nginx.conf"
reject ./update.sh
[[ $(systemctl show -p MainPID --value nginx) == "$oldpid" ]]
sed -i '$d' "$prefix/conf/nginx.conf"
./update.sh --lang zh
cmp sbin/nginx "$prefix/sbin/nginx"
[[ $(systemctl show -p MainPID --value nginx) != "$oldpid" ]]
cp sbin/nginx "$tmp/good"
# Failure injection: validates successfully but cannot start as a service.
printf '#!/bin/sh\ncase "$1" in -v|-t) exit 0;; *) exit 1;; esac\n' > sbin/nginx
reject ./update.sh
cmp "$tmp/good" "$prefix/sbin/nginx"
curl -fsS http://127.0.0.1:18880/ >/dev/null
cp "$tmp/good" sbin/nginx
./uninstall.sh --lang zh
sha256sum -c "$tmp/keep"
[[ ! -e $unit && ! -e $prefix/sbin/nginx ]]
reject ./install.sh
# Inject an external unit to check conflict handling.
install -m 0644 nginx.service "$unit"
systemctl daemon-reload
reject ./install.sh --adopt
rm "$unit"
systemctl daemon-reload
./install.sh --adopt --no-start
systemctl is-enabled nginx.service
reject systemctl is-active --quiet nginx.service
./uninstall.sh
./install.sh --adopt --no-service
./update.sh
[[ ! -e $unit ]]
./uninstall.sh
sha256sum -c "$tmp/keep"
