---
tags:
  - vpn
  - openconnect
  - clash-verge
  - networking
  - vps
---

这篇文章记录了将 Cisco AnyConnect VPN 迁移到 OpenConnect CLI，并最终实现通过 VPS 中转 + SSH 隧道 + Clash Verge 规则分流的完整过程。

## 背景

公司内网需要通过 VPN 访问，之前用的是 Cisco AnyConnect 图形客户端。希望改成命令行方案，并实现分流——公司内网走 VPN，其他流量不受影响。

## 方案演进

### 第一步：OpenConnect 替代 AnyConnect

OpenConnect 是 AnyConnect 的开源替代，兼容 AnyConnect 协议。

```bash
brew install openconnect
```

基本连接命令：

```bash
sudo openconnect 34.92.98.141 \
  --certificate ~/Documents/27a4b7.p12 \
  --cafile ~/Documents/ca-cert.pem \
  -p '证书密码' \
  --background
```

- `--certificate`：PKCS#12 客户端证书
- `--cafile`：CA 根证书
- `-p`：证书密码，避免每次交互输入
- `--background`：后台运行

### 第二步：分流路由脚本（本地方案）

默认 OpenConnect 会替换系统默认网关（全局模式），所有流量走 VPN。通过自定义 vpnc-script 可以实现 split tunneling：

```bash
# ~/.local/bin/vpn-split-route.sh
#!/bin/sh
export CISCO_SPLIT_INC=2
export CISCO_SPLIT_INC_0_ADDR=172.16.0.0
export CISCO_SPLIT_INC_0_MASK=255.255.0.0
export CISCO_SPLIT_INC_0_MASKLEN=16
export CISCO_SPLIT_INC_0_PROTOCOL=0
export CISCO_SPLIT_INC_0_SPORT=0
export CISCO_SPLIT_INC_0_DPORT=0

export CISCO_SPLIT_INC_1_ADDR=16.163.36.97
export CISCO_SPLIT_INC_1_MASK=255.255.255.255
export CISCO_SPLIT_INC_1_MASKLEN=32
export CISCO_SPLIT_INC_1_PROTOCOL=0
export CISCO_SPLIT_INC_1_SPORT=0
export CISCO_SPLIT_INC_1_DPORT=0

. /opt/homebrew/etc/vpnc/vpnc-script
```

通过覆盖 `CISCO_SPLIT_INC` 环境变量，强制只路由指定网段，不改默认网关。

**问题**：部分公司服务虽然域名解析到公网 IP，但只允许从 VPN 网关出去的流量访问，分流路由方案下出口 IP 不对，无法访问。

### 第三步：ocproxy SOCKS5 代理（本地方案）

ocproxy 可以把 VPN 隧道转换成一个本地 SOCKS5 代理：

```bash
brew install ocproxy

sudo openconnect 34.92.98.141 \
  --certificate ~/Documents/27a4b7.p12 \
  --cafile ~/Documents/ca-cert.pem \
  -p '证书密码' \
  --script-tun --script "ocproxy -D 9080" \
  --background
```

连上后 `socks5://127.0.0.1:9080` 可用，内外网都能通。

**问题**：Mac 息屏/休眠后 VPN 连接会断。

### 第四步：VPS 中转（最终方案）

将 OpenConnect + ocproxy 放到 VPS 上常驻运行，解决断连问题。

#### VPS 端配置

```bash
# 安装
apt-get install openconnect ocproxy

# 启动（绑定 127.0.0.1，不对外暴露）
nohup openconnect 34.92.98.141 \
  --certificate ~/27a4b7.p12 \
  --cafile ~/ca-cert.pem \
  -p '证书密码' \
  --script-tun --script 'ocproxy -D 127.0.0.1:9080' \
  --background > /var/log/openconnect.log 2>&1
```

#### 本地 SSH 隧道

通过 SSH 隧道将 VPS 的 9080 端口映射到本地：

```bash
ssh -N -f -L 127.0.0.1:9080:127.0.0.1:9080 vultr
```

#### 开机自启（macOS launchd）

创建 `~/Library/LaunchAgents/com.vpn.ssh-tunnel.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vpn.ssh-tunnel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/ssh</string>
        <string>-N</string>
        <string>-L</string>
        <string>127.0.0.1:9080:127.0.0.1:9080</string>
        <string>-o</string>
        <string>ServerAliveInterval=60</string>
        <string>-o</string>
        <string>ServerAliveCountMax=3</string>
        <string>-o</string>
        <string>ExitOnForwardFailure=yes</string>
        <string>vultr</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/tmp/ssh-tunnel.err</string>
</dict>
</plist>
```

加载：`launchctl load ~/Library/LaunchAgents/com.vpn.ssh-tunnel.plist`

特性：开机自启 + 断线自动重连。

#### Clash Verge 配置

创建独立的本地配置文件 `~/Documents/company-vpn.yaml`，在 Clash Verge 中导入：

```yaml
mixed-port: 7897
allow-lan: false
mode: rule
log-level: info

dns:
  enable: true
  enhanced-mode: fake-ip
  nameserver:
    - 8.8.8.8
    - 1.1.1.1

proxies:
  - name: "VPN-OpenConnect"
    type: socks5
    server: 127.0.0.1
    port: 9080

proxy-groups:
  - name: "Company-VPN"
    type: select
    proxies:
      - "VPN-OpenConnect"
      - "DIRECT"

rules:
  - DOMAIN-SUFFIX,nqsf9emow.com,Company-VPN
  - DOMAIN-SUFFIX,96cftrial.com,Company-VPN
  - DOMAIN-SUFFIX,resininvest.com,Company-VPN
  - IP-CIDR,35.220.178.180/32,Company-VPN,no-resolve
  - IP-CIDR,18.167.151.206/32,Company-VPN,no-resolve
  - IP-CIDR,34.92.83.62/32,Company-VPN,no-resolve
  - IP-CIDR,172.16.0.0/16,Company-VPN,no-resolve
  - MATCH,DIRECT
```

在 Clash Verge 订阅页面「新建 → Local」导入，切换到此配置即可。需要翻墙时切回 Super Flash 订阅。

## 最终架构

```
Mac (Clash Verge) → SSH 隧道 → VPS (ocproxy :9080) → OpenConnect VPN → 公司内网
                  → 其他流量 → DIRECT（或 Super Flash 代理）
```

## 同事共享

同事可以通过 SSH 隧道使用同一个 VPS 上的 VPN：

1. 同事生成 SSH 密钥：`ssh-keygen`
2. 将公钥加到 VPS 的 `~/.ssh/authorized_keys`
3. 同事本地执行：`ssh -N -f -L 127.0.0.1:9080:127.0.0.1:9080 root@64.176.50.5`
4. 导入 `company-vpn.yaml` 到 Clash Verge

## 关键文件

| 文件 | 用途 |
|------|------|
| `~/Documents/27a4b7.p12` | 客户端证书 |
| `~/Documents/ca-cert.pem` | CA 根证书 |
| `~/Documents/company-vpn.yaml` | Clash Verge 本地配置 |
| `~/.local/bin/vpn-connect.sh` | 本地直连 VPN 脚本（备用） |
| `~/.local/bin/vpn-split-route.sh` | 分流路由脚本（备用） |
| `~/Library/LaunchAgents/com.vpn.ssh-tunnel.plist` | SSH 隧道开机自启 |

## 常用命令

```bash
# 查看 SSH 隧道状态
lsof -i :9080 -P -n

# 手动启动 SSH 隧道
ssh -N -f -L 127.0.0.1:9080:127.0.0.1:9080 vultr

# 测试公司内网访问
curl --socks5-hostname 127.0.0.1:9080 http://jjaa.nqsf9emow.com:29080

# VPS 上查看 VPN 状态
ssh vultr "pgrep -la openconnect; ss -tlnp | grep 9080"

# VPS 上重启 VPN
ssh vultr "kill \$(pgrep openconnect); nohup openconnect 34.92.98.141 --certificate ~/27a4b7.p12 --cafile ~/ca-cert.pem -p '证书密码' --script-tun --script 'ocproxy -D 127.0.0.1:9080' --background > /var/log/openconnect.log 2>&1"

# 断开本地 SSH 隧道
kill $(lsof -t -i :9080)
```
