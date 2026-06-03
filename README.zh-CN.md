# RayLite

[English README](./README.md)

**RayLite** 是一个用于 Linux VPS 的一键部署脚本，目标是部署 **VMess + WebSocket + TLS + 伪装域名 + 可选 Cloudflare 反向代理**。

它主要面向小型 VPS，尤其适合 **1 核 / 512 MB 内存** 这类低配机器。服务端只通过 Nginx 暴露一个 WebSocket 路由 `/ray`，其他普通路径表现为一个极简静态网站，从而让域名看起来像普通 HTTPS 站点。

```text
客户端
  -> Cloudflare 反向代理，可选
  -> https://your-domain.example/ray
  -> Nginx :443
  -> 127.0.0.1:10086
  -> V2Ray Core VMess inbound
```


## 最简单用法

RayLite 的目标就是尽量傻瓜式部署：

```text
1. 先在 Cloudflare 里配置好域名 / 子域名到 VPS 公网 IP 的解析。
2. SSH 登录 VPS。
3. 执行一条命令。
4. 导入脚本自动生成的 VMess 客户端链接。
```

示例：

```bash
git clone https://github.com/janeuler/RayLite.git
cd RayLite
chmod +x setup-raylite.sh
sudo env DOMAIN=v1.example.com bash setup-raylite.sh --yes
```

默认部署不需要你提前准备 UUID。脚本会自动生成 UUID，并同时写入服务端配置和客户端配置。安装完成后，直接查看可导入的客户端链接：

```bash
cat /root/raylite/client/v1.example.com.vmess.txt
```

默认技术栈：

```text
VMess + WebSocket + TLS + /ray + Nginx 伪装页面 + 可选 Cloudflare 反向代理
```

对普通用户来说，执行脚本前唯一必须手动准备的是域名解析：

```text
Cloudflare DNS：
A 记录 -> VPS 公网 IP
SSL/TLS -> Full 或 Full (strict)
Network -> WebSockets -> On
```

复杂参数、故障排查、生成文件位置、手动配置说明都放在后文详细说明。

## 功能特性

- 通过 V2Fly 官方 FHS 安装脚本安装 V2Ray Core。
- 自动识别常见 Linux 发行版和包管理器。
- 自动生成 UUID，用于服务端和客户端验证。
- 部署 VMess over WebSocket + TLS。
- 默认使用 `/ray` 作为 WebSocket 转发路由。
- 自动写入 Nginx 伪装站点和 WebSocket 反向代理配置。
- 使用 Certbot standalone 模式申请 Let's Encrypt 证书。
- 自动写入 Certbot standalone 续期 hooks。
- 可选创建 swap，适配小内存 VPS。
- 可选写入 TCP/BBR 优化参数。
- 自动配置 UFW 或 firewalld，如果系统存在对应防火墙工具。
- 自动生成客户端可直接导入的配置文件。
- 安装结束时输出所有生成和修改的文件位置。

## 支持的系统

RayLite 面向 **systemd 系 Linux 发行版**。

| 系列 | 发行版 |
|---|---|
| Debian 系 | Debian、Ubuntu、Linux Mint、Pop!_OS、Zorin、Kali |
| Fedora 系 | Fedora |
| RHEL 系 | RHEL、CentOS、Rocky Linux、AlmaLinux、Oracle Linux |
| Arch 系 | Arch Linux、Manjaro、EndeavourOS |
| SUSE 系 | openSUSE Leap、openSUSE Tumbleweed、SLES |

支持的包管理器：

```text
apt, dnf, yum, pacman, zypper
```

不推荐环境：

```text
Alpine Linux、OpenWrt、非 systemd 系统、没有真实 systemd 的容器、共享虚拟主机
```

## 默认部署内容

```text
协议：              VMess
传输层：            WebSocket
TLS：               开启
公网端口：          443
WebSocket 路径：    /ray
Nginx 路由：        location = /ray
V2Ray 监听地址：    127.0.0.1
V2Ray 本地端口：    10086
alterId：           0
加密：              auto
```

默认公网行为：

```text
https://your-domain.example/       -> 伪装首页
https://your-domain.example/ray    -> WebSocket 反向代理到 V2Ray
其他不存在路径                     -> 404/静态站点行为
```

## 安装前的 Cloudflare 配置

先创建 DNS 记录：

```text
类型：A
名称：v1、proxy、ray，或者你自己喜欢的子域名前缀
内容：你的 VPS 公网 IPv4
```

推荐 Cloudflare 配置：

```text
SSL/TLS -> Overview -> Full 或 Full (strict)
Network -> WebSockets -> On
```

RayLite 使用 Certbot standalone 模式做 HTTP-01 证书验证。申请证书时，VPS 的 TCP `80` 端口必须可以被访问。

如果 Cloudflare 后面申请证书失败，优先检查：

```text
1. 域名是否指向 VPS。
2. VPS 防火墙和云厂商安全组是否放行 TCP 80 和 443。
3. 申请证书期间 Cloudflare 的 Always Use HTTPS 是否关闭。
4. 如果橙云代理模式失败，可以先临时切到 DNS only 灰云，重新执行脚本，成功后再切回 Proxied 橙云。
```

## 快速开始

```bash
git clone https://github.com/your-name/RayLite.git
cd RayLite
chmod +x setup-raylite.sh
sudo env DOMAIN=v1.example.com EMAIL=admin@example.com bash setup-raylite.sh --yes
```

不填写邮箱的最小命令：

```bash
sudo env DOMAIN=v1.example.com bash setup-raylite.sh --yes
```

自定义 WebSocket 路径和本地 V2Ray 端口：

```bash
sudo env DOMAIN=v1.example.com \
  WS_PATH=/ray \
  V2_PORT=10086 \
  EMAIL=admin@example.com \
  bash setup-raylite.sh --yes
```

只生成客户端配置：

```bash
bash setup-raylite.sh \
  --client-only \
  --domain v1.example.com \
  --uuid xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

预览执行结果，不修改系统：

```bash
bash setup-raylite.sh \
  --dry-run \
  --root-dir /tmp/raylite-preview \
  --domain v1.example.com \
  --cert-mode none \
  --yes
```

## 脚本参数

```text
--domain DOMAIN          必填域名，例如 v1.example.com
--email EMAIL            可选 Let's Encrypt 邮箱
--ws-path PATH           WebSocket 路径，默认 /ray
--v2-port PORT           本地 V2Ray 端口，默认 10086
--uuid UUID              可选自定义 UUID；如果为空则自动生成
--ps NAME                客户端配置名称
--output-dir DIR         输出目录，默认 /root/raylite
--web-root DIR           静态伪装站点根目录，默认 /var/www/raylite/DOMAIN
--ssh-port PORT          防火墙放行的 SSH 端口，默认 22
--no-firewall            不配置 ufw/firewalld
--no-swap                不创建 swap
--no-bbr                 不写入 TCP/BBR sysctl 参数
--staging                使用 Let's Encrypt staging 环境
--force-cert-renew       即使已有证书也重新申请
--cert-mode MODE         standalone 或 none，默认 standalone
--dry-run                只打印计划，不修改系统
--root-dir DIR           配合 --dry-run，把预览文件写入指定目录
--client-only            只生成客户端 JSON 和 vmess:// 链接，不需要 root
-y, --yes                非交互确认
-h, --help               查看帮助
```

也支持环境变量：

```text
DOMAIN, EMAIL, WS_PATH, V2_PORT, UUID, PS, OUTPUT_DIR, WEB_ROOT, SSH_PORT,
ENABLE_FIREWALL, ADD_SWAP, SWAP_SIZE, ENABLE_BBR, CERT_STAGING,
FORCE_CERT_RENEW, CERT_MODE, V2RAY_INSTALL_URL, DRY_RUN, ROOT_DIR,
CLIENT_ONLY, ASSUME_YES
```

## 生成和修改的文件

典型服务端文件：

```text
/usr/local/etc/v2ray/config.json
/etc/systemd/system/v2ray.service.d/20-raylite-user.conf
/etc/nginx/conf.d/00-raylite-websocket-map.conf
/etc/nginx/conf.d/raylite-your-domain.conf
/etc/sysctl.d/99-raylite.conf
/var/www/raylite/your-domain/index.html
/etc/letsencrypt/renewal-hooks/pre/raylite-stop-nginx.sh
/etc/letsencrypt/renewal-hooks/post/raylite-start-nginx.sh
```

典型客户端文件：

```text
/root/raylite/client/your-domain.json
/root/raylite/client/your-domain.vmess.txt
/root/raylite/client/your-domain.v2ray-client.json
/root/raylite/install-report-your-domain-YYYYMMDD-HHMMSS.txt
```

脚本执行结束时会打印所有生成和修改的文件位置。

## 客户端导入

安装完成后查看 VMess 导入链接：

```bash
cat /root/raylite/client/v1.example.com.vmess.txt
```

复制后导入支持 VMess 的客户端即可。

等价客户端参数：

```text
协议：              VMess
地址：              你的域名
端口：              443
UUID：              脚本生成
alterId：           0
加密：              auto
传输：              WebSocket
路径：              /ray
Host：              你的域名
TLS：               开启
SNI：               你的域名
Allow insecure：    false
```

`your-domain.v2ray-client.json` 可以直接给 V2Ray Core 作为本地客户端配置使用。它默认提供：

```text
SOCKS：127.0.0.1:10808
HTTP： 127.0.0.1:10809
```

## 验证安装

检查服务：

```bash
nginx -t
systemctl status nginx
/usr/local/bin/v2ray test -config /usr/local/etc/v2ray/config.json
systemctl status v2ray
```

检查端口：

```bash
ss -lntp
```

预期结果：

```text
0.0.0.0:80        nginx
0.0.0.0:443       nginx
127.0.0.1:10086   v2ray
```

测试首页：

```bash
curl -I https://v1.example.com/
```

测试 WebSocket 路由：

```bash
curl -v --http1.1 \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  https://v1.example.com/ray
```

结果理解：

```text
101 Switching Protocols -> 理想的 WebSocket upgrade 结果
400/405 from /ray       -> 通常说明请求到达了 V2Ray/WebSocket 层，但测试请求不是完整 VMess 会话
timeout                 -> 优先检查 DNS、防火墙、Cloudflare、Nginx、云厂商安全组
```

## 需要手动确认的配置

执行脚本前：

```text
1. 配好域名 DNS A 记录。
2. 云厂商安全组放行 TCP 80 和 443。
3. 保证 SSH 仍可连接。
4. 如果使用 Cloudflare，打开 WebSockets。
5. 如果使用 Cloudflare，SSL/TLS 使用 Full 或 Full (strict)。
```

执行脚本后：

```text
1. 把 /root/raylite/client/your-domain.vmess.txt 导入客户端。
2. 检查客户端 Host 和 SNI 是否都是你的域名。
3. 检查 WebSocket path 是否正好是 /ray，除非你自己改过。
4. 如果 Certbot 失败，先切换 Cloudflare DNS only，再重新执行。
5. 如果 Nginx 无法加载 /etc/nginx/conf.d/ 下的配置，需要手动查看 /etc/nginx/nginx.conf。
```

## 排错

查看日志：

```bash
journalctl -u nginx -n 100 --no-pager
journalctl -u v2ray -n 100 --no-pager
```

查看 Nginx 完整配置：

```bash
nginx -T | sed -n '1,260p'
```

查看 V2Ray 配置：

```bash
sed -n '1,220p' /usr/local/etc/v2ray/config.json
```

测试证书续期：

```bash
certbot renew --dry-run
```

## 安全说明

- UUID 不要公开。
- 不要把生成的客户端配置上传到公开仓库。
- SSH 尽量使用密钥登录。
- 定期更新系统。
- 建议使用专门的子域名。
- 512 MB VPS 不建议再跑 Docker、数据库、面板等重服务。

## 免责声明

本项目用于合法的个人网络访问、私有基础设施访问和服务器配置学习。使用者需要自行遵守所在地法律法规、服务商条款和网络使用政策。

## 致谢

特别感谢：

- [V2Fly / V2Ray Core](https://github.com/v2fly/v2ray-core)
- [fhs-install-v2ray](https://github.com/v2fly/fhs-install-v2ray)
- [Nginx](https://nginx.org/)
- [Let's Encrypt](https://letsencrypt.org/)
- [Certbot](https://certbot.eff.org/)
- [Debian](https://www.debian.org/)
- [Ubuntu](https://ubuntu.com/)
- [Fedora](https://fedoraproject.org/)
- [Arch Linux](https://archlinux.org/)
- [openSUSE](https://www.opensuse.org/)
- [Cloudflare](https://www.cloudflare.com/)
- 开源社区

## 许可证

RayLite 使用 [GNU General Public License v3.0](./LICENSE)（GPL-3.0-only）开源。
