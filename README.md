# nginx-unofficial-builds

从 [nginx 官方稳定版](https://nginx.org/en/download.html)源码编译 Linux 静态二进制，提供 x86_64（AMD64）和 aarch64（ARM64）两种压缩包。包含默认配置、HTML、HTTPS、HTTP/2 和 stream 模块。构建方式参考 [jirutka/nginx-binaries](https://github.com/jirutka/nginx-binaries)。

GitHub Actions 每天北京时间 09:23 和 21:23 检查稳定版，也可在 Actions 页面手动运行。新版本在两种架构上分别编译、解包、检查配置并测试 HTTP 服务，均通过后上传至 [Releases](https://github.com/ainuoyan/nginx-unofficial-builds/releases)。

nginx 使用上游默认安装目录 `/usr/local/nginx`。安装在该目录时可直接运行 `/usr/local/nginx/sbin/nginx -t` 检查配置。

如需在其他目录运行，下载本机架构的包和同一 Release 的 SHA256SUMS，在下载目录执行：

```sh
sha256sum --ignore-missing -c SHA256SUMS
tar xzf nginx-<版本>-linux-<架构>.tar.gz
cd nginx-<版本>-linux-<架构>
./sbin/nginx -p "$PWD/" -t
./sbin/nginx -p "$PWD/"
```

将示例中的占位符换成实际版本和架构。默认监听 80 端口，普通用户可先修改 conf/nginx.conf 中的 listen 端口。停止时执行 `./sbin/nginx -p "$PWD/" -s quit`。

### Linux 部署

校验并解压安装包后，在包目录执行以下脚本。需要 Linux、Bash、flock 和 pgrep；注册服务需要 systemd。默认提示为英文，各入口均支持 `--lang zh` 和 `--help`。

| 操作 | 命令 |
|---|---|
| 安装、启动并设为开机启动 | `sudo ./install.sh --lang zh` |
| 安装并启用服务，暂不启动 | `sudo ./install.sh --no-start` |
| 仅安装文件，手动管理进程 | `sudo ./install.sh --no-service` |
| 从新包升级（含同版本重新打包） | `sudo ./update.sh --lang zh` |
| 卸载服务和二进制，保留配置、证书、网页和日志 | `sudo ./uninstall.sh --lang zh` |

接管已有默认路径安装时，先确认原配置位置、停止原进程，再使用 `--adopt`。已有外部服务应由原管理方式处理。配置变更后使用 `sudo /usr/local/nginx/sbin/nginx -t && sudo systemctl reload nginx`。升级正在运行的受管服务会短暂重启；使用手动模式时请先停止 nginx 再升级。
