# Shared by the three package entry points.
set -euo pipefail
pkg=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
prefix=/usr/local/nginx
bin=$prefix/sbin/nginx
state=$prefix/.unofficial-build
unit=/etc/systemd/system/nginx.service
lang=en
no_service=false
no_start=false
adopt=false
help=false

say() { if [[ $lang == zh ]]; then echo "$2"; else echo "$1"; fi; }
fail() { say "$1" "$2" >&2; exit 1; }
while (( $# )); do
    case "$1" in
        --lang) shift; lang=${1:-}; [[ $lang == en || $lang == zh ]] || fail 'Use --lang en|zh' '请使用 --lang en|zh' ;;
        -h|--help) help=true ;;
        --no-service|--no-start|--adopt)
            [[ $operation == install ]] || fail "Invalid option: $1" "无效选项：$1"
            case "$1" in
                --no-service) no_service=true ;;
                --no-start) no_start=true ;;
                --adopt) adopt=true ;;
            esac ;;
        *) fail "Unknown option: $1" "未知选项：$1" ;;
    esac
    shift
done
if "$help"; then
    say "Usage: sudo ./$operation.sh [--lang en|zh]" "用法：sudo ./$operation.sh [--lang en|zh]"
    case $operation in
        install) say '--no-start: enable without starting; --no-service: files only; --adopt: adopt a stopped default-prefix installation' '--no-start 注册但暂不启动；--no-service 仅安装文件；--adopt 接管已停止的默认路径安装' ;;
        update) say 'Validate configuration, replace the binary and restart an active managed service.' '检查现有配置，替换程序并重启正在运行的受管服务。' ;;
        uninstall) say 'Remove the managed binary and service; keep configuration, site files and logs.' '移除受管程序和服务，保留配置、站点和日志。' ;;
    esac
    exit 0
fi
[[ $(uname -s) == Linux && $EUID == 0 ]] || fail 'Run as root on Linux.' '请在 Linux 上以 root 运行。'
exec 9>/run/nginx-unofficial-builds.lock
flock -n 9 || fail 'Another deployment is running.' '另一个部署正在运行。'
# Never follow installation or ownership-marker symlinks during privileged mutations.
for path in "$prefix" "$prefix/sbin" "$bin" "$state"; do
    if [[ -e $path ]]; then
        owner=$(stat -c %u "$path")
        perms=$(stat -c %a "$path")
        [[ $owner == 0 && $((8#$perms & 022)) == 0 ]] ||
            fail "Unsafe ownership or permissions: $path" "路径属主或权限不安全：$path"
    fi
    [[ ! -L $path ]] || fail "Unexpected symbolic link: $path" "路径为符号链接：$path"
done
managed=false
mode=files
if [[ -f $state ]]; then
    read -r mode < "$state"
    [[ $mode == files || $mode == systemd ]] || fail 'Invalid installation marker.' '安装标记无效。'
    managed=true
fi
if [[ $operation != install ]] && ! "$managed"; then
    fail 'No managed installation found.' '未找到受管安装。'
fi
if [[ $operation == install ]] && "$managed"; then
    fail 'Already installed. Use update.sh.' '已经安装，请使用 update.sh。'
fi
if [[ $mode == systemd ]] || { [[ $operation == install ]] && ! "$no_service"; }; then
    fragment=$(systemctl show -p FragmentPath --value nginx.service)
    if [[ $mode == systemd ]]; then
        [[ $fragment == "$unit" && ! -L $unit ]] && cmp -s "$pkg/nginx.service" "$unit" ||
            fail 'Managed service definition changed.' '受管服务定义已变更。'
    elif [[ -n $fragment || -e $unit || -L $unit ]]; then
        fail "Existing service: $fragment" "已存在服务：$fragment"
    fi
fi
if [[ $mode == files ]] && pgrep -x nginx >/dev/null; then
    fail 'Stop the existing nginx before deploying.' '部署前请停止现有 nginx。'
fi
if [[ $operation == uninstall ]]; then
    if [[ $mode == systemd ]]; then
        systemctl disable --now nginx.service
        rm -- "$unit"
        systemctl daemon-reload
    fi
    rm -f -- "$bin" "$state"
    say 'Uninstalled. Site files were preserved.' '卸载完成，已保留现场文件。'
    exit 0
fi

read -r arch < "$pkg/ARCH"
[[ $(uname -m) == "$arch" ]] || fail "Package architecture: $arch" "安装包架构：$arch"
"$pkg/sbin/nginx" -v
if [[ $operation == install && -d $prefix ]]; then
    "$adopt" || fail "Existing $prefix; inspect it and use --adopt." "已存在 $prefix，请核对后使用 --adopt。"
    if [[ -e $bin ]]; then
        say "Inspecting $bin; expected configuration: $prefix/conf/nginx.conf" "检查 $bin，预期配置：$prefix/conf/nginx.conf"
        # nginx -V may omit the prefix when it is the compiled default.
        opts=$("$bin" -V 2>&1)
        for opt in $opts; do
            case "$opt" in
                --prefix=/usr/local/nginx|--conf-path=conf/nginx.conf|--conf-path=/usr/local/nginx/conf/nginx.conf) ;;
                --prefix=*|--conf-path=*) fail "Configuration layout differs: $opt" "配置路径不同：$opt" ;;
            esac
        done
    fi
    [[ -f $prefix/conf/nginx.conf ]] || fail 'Missing existing nginx.conf.' '未找到现有 nginx.conf。'
fi
mkdir -p "$prefix/sbin"
if [[ $operation == install ]] && ! "$adopt"; then
    cp -R "$pkg/conf" "$pkg/html" "$prefix/"
    mkdir -p "$prefix/logs"
fi
"$pkg/sbin/nginx" -t
if [[ $operation == update ]] && cmp -s "$pkg/sbin/nginx" "$bin"; then
    say 'Identical binary already installed.' '已安装相同的二进制。'
    exit 0
fi
tmp=$(mktemp -d "$prefix/sbin/.deploy.XXXXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
[[ ! -f $bin ]] || cp -p "$bin" "$tmp/previous"
install -m 0755 "$pkg/sbin/nginx" "$tmp/new"
active=false
if [[ $mode == systemd ]] && systemctl is-active --quiet nginx.service; then active=true; fi
mv -f "$tmp/new" "$bin"
restore_binary() {
    if [[ -f $tmp/previous ]]; then mv -f "$tmp/previous" "$bin"; else rm -f "$bin"; fi
}
if [[ $operation == install ]]; then
    if ! "$no_service"; then
        if ! { install -m 0644 "$pkg/nginx.service" "$unit" && systemctl daemon-reload &&
               systemctl enable nginx.service && { "$no_start" || systemctl start nginx.service; }; }; then
            systemctl disable --now nginx.service || true
            rm -f "$unit"
            systemctl daemon-reload
            restore_binary
            fail 'Service installation failed; binary restored.' '服务安装失败，已撤回程序替换。'
        fi
        mode=systemd
    fi
    printf '%s\n' "$mode" > "$state"
elif "$active" && ! systemctl restart nginx.service; then
    restore_binary
    if systemctl restart nginx.service; then
        fail 'Update failed; previous binary and service restored.' '升级失败，已恢复原程序和服务。'
    fi
    fail 'Previous binary restored; service recovery failed.' '已恢复原程序，服务恢复失败。'
fi
say 'Deployment complete.' '部署完成。'
