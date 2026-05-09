## 写在前面

本文给完全没有搭过梯子的新手，介绍 2026 年抗封锁性最强的 **VLESS + Reality** 方案，使用 **3x-ui** 面板部署，**只需要一台裸 IP 的 VPS，不需要域名、不需要证书、不需要 Cloudflare**。文章覆盖：协议选型、VPS 选购、面板搭建、订阅获取（Clash / Shadowsocks）、客户端导入、运维与加固。

## 懒人模式：丢给 AI 自动搭建

如果你手里有 Claude Code / Cursor / 任何能 SSH 的 AI 助手，整个搭建过程**只剩"买 VPS"这一步是人工**，剩下全自动。买完后把 SSH 凭据丢给 AI，加上下面这段提示词：

```text
我有一台全新的 Ubuntu 22.04 / Debian 12 VPS，凭据如下：
  IP:       x.x.x.x
  user:     root
  password: xxxxxxxx

请你 SSH 上去，按下面要求搭建一套翻墙服务：

1. 基础加固
   - SSH 端口改成 22000（或随机一个 10000-65000）
   - 安装 ufw 防火墙，只放行 SSH / 443 / 80 / 面板端口 / 订阅端口
   - 开启 BBR
   - 时区设为 Asia/Shanghai

2. 安装 3x-ui 面板（https://github.com/MHSanaei/3x-ui）
   - 面板端口随机生成（10000-65000）
   - 面板 Web Path 随机字符串
   - 用户名/密码随机生成（强密码）
   - 安装脚本是交互式的，请用 expect 自动应答，或安装完成后直接用 `x-ui` 命令重置配置

3. 创建一条 VLESS + Reality 入站
   - 端口 443
   - Flow: xtls-rprx-vision
   - Dest / ServerNames: www.microsoft.com:443
   - 自动生成 UUID / Reality 公私钥 / shortIds
   - 创建一个客户端，邮箱标识为 main

4. 创建一条 Shadowsocks 入站作为兜底
   - 端口 8388
   - 加密: 2022-blake3-aes-256-gcm（或 chacha20-ietf-poly1305）
   - 密码自动生成

5. 启用订阅服务
   - 订阅端口 2096
   - 路径 /sub/ 和 /json/

6. 最终输出给我一份 markdown 格式的"交付清单"，至少包含：

   **服务器信息**
   - 新 SSH 端口 + 完整登录命令
   - 面板 URL / 用户名 / 密码

   **订阅链接（按客户端分组，方便我直接粘贴）**
   - 🖥 **Clash Verge / Clash Verge Rev / Mihomo / Stash**（macOS / Windows / Linux）：
     base64 订阅 URL → `http://IP:2096/sub/xxxx`
   - 📱 **Shadowrocket**（iOS）：
     同上 base64 订阅 URL（Shadowrocket 原生支持 VLESS+Reality 和 SS）
   - 🤖 **v2rayN / v2rayNG**（Windows / Android）：
     同上 base64 订阅 URL
   - 🧪 **sing-box / Clash.Meta（高级用户）**：
     JSON 订阅 URL → `http://IP:2096/json/xxxx`

   **单节点链接（备用，复制单条节点用）**
   - vless:// 链接
   - ss:// 链接
   - 二维码（终端 ASCII 输出，方便手机扫）

注意事项：
- 所有交互式命令请用 expect 或非交互参数完成，不要等我手动输入
- 如果 3x-ui API 不方便调用，可以直接改 /etc/x-ui/x-ui.db（SQLite）
- Reality 公私钥用 `/usr/local/x-ui/bin/xray x25519` 生成
- 完成后请打印一份 markdown 格式的"交付清单"，我可以直接保存
```

AI 跑完后你拿到订阅链接，直接粘到客户端（Clash Verge / Shadowrocket）就能用。整个过程从拿到 SSH 到能上网大概 **5–10 分钟**。

下面是给"想自己搞清楚每一步在做什么"的读者的完整图文版。

## 一、协议对比：为什么不选 Shadowsocks 和 V2Ray

| 协议 | 抗封锁 | 速度 | 配置难度 | 现状 |
|---|---|---|---|---|
| Shadowsocks (SS) | ⭐⭐ | 快 | 低 | 流量特征明显，2020 年后大规模被 GFW 主动探测，重大节日基本必死 |
| ShadowsocksR (SSR) | ⭐ | 快 | 低 | 已停止维护，不推荐 |
| VMess (V2Ray) | ⭐⭐ | 中 | 中 | 早期主流，2022 年后特征被识别，裸 VMess 不可用 |
| VMess + WS + TLS + CDN | ⭐⭐⭐ | 慢 | 中 | 套 Cloudflare 还能用，但 CF IP 经常被限速封禁 |
| Trojan | ⭐⭐⭐ | 快 | 中 | 伪装成 HTTPS，需要域名+证书，主动探测时回源会暴露 |
| Trojan-Go | ⭐⭐⭐ | 快 | 中 | Trojan 升级版，依然依赖域名 |
| Hysteria2 | ⭐⭐⭐⭐ | 极快 (UDP/QUIC) | 中 | 速度王者，但 UDP 容易被运营商 QoS 限速 |
| TUIC v5 | ⭐⭐⭐⭐ | 极快 | 中 | 类似 Hysteria，QUIC 多路复用 |
| NaiveProxy | ⭐⭐⭐⭐ | 中 | 高 | Chrome 网络栈，伪装最强但配置复杂 |
| **VLESS + Reality** | ⭐⭐⭐⭐⭐ | 快 | 低（有面板） | **当前最优解** |
| WireGuard / OpenVPN | ⭐ | — | 低 | 流量特征极强，国内基本不可用 |

**结论：2026 年首选 VLESS + Reality，备用 Hysteria2，互相兜底。**

> Reality 的核心优势：无需自己的域名/证书，借用 microsoft.com / apple.com 等大站做 TLS 握手，GFW 主动探测看到的就是真实大站证书，没法区分真假。

> 至于为什么后面还会讲 Shadowsocks 订阅——不是因为它强，而是很多老客户端（部分路由器固件、老版本工具）只支持 SS，所以面板会顺便把节点导出成 SS 链接做兼容。SS 在这里只是"客户端兼容方案"，不是主力。

## 二、面板选型

裸装 Xray 配置 JSON 太痛苦，新手一定要用面板。

| 面板 | 推荐度 | 说明 |
|---|---|---|
| **3x-ui** | ⭐⭐⭐⭐⭐ | 社区最活跃，原生支持 Reality / Hysteria2 / TUIC，自带流量统计、订阅、Telegram Bot |
| x-ui (原版) | ⭐⭐ | 已停更，3x-ui 是它的接班 |
| Marzban | ⭐⭐⭐⭐ | 多用户/多节点管理，企业级，部署麻烦 |
| Hiddify | ⭐⭐⭐⭐ | 一键脚本最完善，集成度高，适合"完全不想动脑" |
| sing-box (裸装) | ⭐⭐ | 协议最全但要自己写配置，新手别碰 |

本文使用 **3x-ui**。

## 三、VPS 选购

### 推荐机房

| 机房 | 优点 | 缺点 |
|---|---|---|
| Vultr（东京 / 大阪 / 新加坡 / 洛杉矶） | 按小时计费，IP 能换（销毁后重开），$3.5/月起 | 新加坡延迟好但有时丢包 |
| DigitalOcean | 稳定，$4/月起 | 中国线路一般 |
| BandwagonHost (搬瓦工) CN2 GIA | 国内直连最快 | 贵（$10+/月），IP 一旦封难换 |
| AWS Lightsail 东京 | 便宜稳定 | IP 池被识别风险高 |
| Oracle Cloud Always Free | 永久免费 | 申请门槛高，IP 经常被封 |

**新手推荐**：Vultr 东京 / 大阪，$6/月规格，IP 被封了销毁重建只损失几小时费用。

### 选购要点
- **位置**：日韩（低延迟）> 美西 > 欧洲
- **带宽**：≥1Gbps 端口，≥1TB/月流量
- **IPv4**：必须有独立 IPv4
- **系统**：Ubuntu 22.04 / Debian 12（本文以此为例）

## 四、初始环境准备

SSH 登录后先做基础加固：

```bash
# 1. 更新系统
apt update && apt upgrade -y

# 2. 设置时区（证书 / Reality 时间戳依赖）
timedatectl set-timezone Asia/Shanghai

# 3. 安装基础工具
apt install -y curl wget vim ufw socat

# 4. 改 SSH 端口（强烈建议，挡 90% 暴力破解）
sed -i 's/#Port 22/Port 22000/' /etc/ssh/sshd_config
systemctl restart ssh

# 5. 防火墙
ufw allow 22000/tcp     # 你的新 SSH 端口
ufw allow 443/tcp       # Reality 入口
ufw allow 80/tcp
ufw --force enable

# 6. 开启 BBR 加速（明显提升速度）
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

# 验证 BBR 已启用
sysctl net.ipv4.tcp_congestion_control   # 应输出 bbr
```

## 五、安装 3x-ui

官方一键脚本：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
```

安装过程会问你：

1. **是否自定义面板配置？** → `y`
2. **用户名** → 改成不易猜的（不要用 admin）
3. **密码** → 强密码
4. **面板端口** → 改成 10000–65000 之间一个奇怪端口（例如 `52718`）
5. **面板路径**（Web Path）→ 改成随机字符串（例如 `xj9k2lm`），访问地址就变成 `http://IP:52718/xj9k2lm/`

> 千万不要用默认 2053 端口和默认路径，会被批量扫描。

安装完成后会显示登录信息，**截图保存**。

如果忘了：
```bash
x-ui settings        # 查看当前面板配置
x-ui                 # 进入管理菜单
```

把面板端口加到防火墙：
```bash
ufw allow 52718/tcp   # 换成你的端口
```

## 六、登录面板 + 创建 VLESS Reality 节点

### 1. 访问面板
浏览器打开 `http://你的IP:52718/xj9k2lm/`，用刚才设的账号密码登录。

### 2. 添加入站（Inbound）

点 **入站列表 → 添加入站**：

| 字段 | 值 |
|---|---|
| 备注 | `reality-main`（自己看的） |
| 协议 | **VLESS** |
| 监听 IP | 留空（= 0.0.0.0） |
| 端口 | **443** |
| 总流量 (GB) | 0（不限） |
| 到期时间 | 0（永久） |

往下滑——客户端配置：

| 字段 | 值 |
|---|---|
| 邮箱 | `user1`（标识用户，随便起） |
| 流控 (Flow) | **`xtls-rprx-vision`** |
| ID | 点旁边按钮**生成 UUID** |

**传输 (Transmission)**：
- Network: **tcp**
- Security: **Reality**

**Reality 配置**：

| 字段 | 值 |
|---|---|
| uTLS | `chrome` |
| Dest (目标域名) | `www.microsoft.com:443` 或 `www.cloudflare.com:443` / `www.apple.com:443` / `www.tesla.com:443` |
| Server Names | 与 Dest 一致，例如 `www.microsoft.com` |
| 私钥/公钥 | 点 **"获取新证书"** 自动生成 |
| Short Ids | 点 **"生成"** 自动生成 |
| SpiderX | 留空 |

> Dest 选择原则：跟你 VPS 同区域延迟低、且没被你客户端 ISP 屏蔽的大站。日本机就选 microsoft.com / apple.com，美国机加上 tesla.com。

点 **创建**。

### 3. 可选：再加一条 Hysteria2 兜底

重复上面步骤，协议选 **hysteria2**，端口选个 UDP（例如 36712），防火墙加：
```bash
ufw allow 36712/udp
```

## 七、获取订阅地址（Clash 和 Shadowsocks）

3x-ui 自带订阅服务，很多人没启用。

### 1. 启用订阅服务

面板左侧 **面板设置 → 订阅设置**：

| 字段 | 值 |
|---|---|
| 启用订阅服务 | ✅ 打开 |
| 订阅端口 | `2096`（或随便选个没占用的） |
| 订阅路径 | `/sub/`（默认即可） |
| 订阅 JSON 路径 | `/json/` |
| 订阅域名 | 留空（= 用 IP） |

保存后**重启面板**：
```bash
x-ui restart
```

防火墙放行：
```bash
ufw allow 2096/tcp
```

### 2. 拿到订阅地址

回到 **入站列表**，点 reality 入站右侧的 **操作 → 显示信息**（齿轮图标），里面会看到每个客户端对应的：

- **二维码**（直接扫）
- **vless://** 链接（单节点）
- **订阅链接** —— 重点

订阅链接长这样：
```
http://你的IP:2096/sub/<subId>
```

`<subId>` 是 3x-ui 自动给每个客户端生成的字符串。

**一个客户端有两个订阅链接**：

| 类型 | 路径 | 用途 |
|---|---|---|
| 普通订阅 (Base64) | `http://IP:2096/sub/xxxx` | 给 v2rayN / v2rayNG / Shadowrocket / Clash Verge 用，base64 编码的节点列表 |
| JSON 订阅 | `http://IP:2096/json/xxxx` | 给 sing-box / Clash.Meta 用，结构化配置 |

### 3. Clash 订阅怎么来

3x-ui **不直接生成 Clash YAML**，而是 base64 节点列表。**Clash Verge / Clash Meta / Mihomo / Stash** 这类现代客户端会自动把 base64 转成 Clash 配置，**直接粘贴订阅链接就能用**。

如果用的是只吃 Clash YAML 格式的老客户端，两个办法：

**方案 A：在线订阅转换**
```
https://api.subconverter.com/sub?target=clash&url=<URL编码后的订阅链接>
```
推荐前端：https://acl4ssr-sub.github.io/

**方案 B：自建 subconverter**
```bash
docker run -d --restart=always -p 25500:25500 \
  --name subconverter tindy2013/subconverter:latest
```
然后访问 `http://你的IP:25500/sub?target=clash&url=...`

### 4. Shadowsocks 订阅怎么来

3x-ui 默认**不会**自动给你 SS 节点。需要单独建一条 Shadowsocks 入站：

入站列表 → 添加入站：
- 协议：**Shadowsocks**
- 端口：例如 `8388`
- 加密方式：`chacha20-ietf-poly1305` 或 `2022-blake3-aes-256-gcm`（更新更安全）
- 密码：自动生成

保存后，订阅链接里就会自动包含 `ss://` 节点。

> ⚠️ SS 节点容易被探测，**只在客户端不支持 VLESS 时才用**（比如某些老路由器）。日常用 VLESS Reality 就够了。

## 八、客户端配置

| 平台 | 推荐客户端 | 导入方式 |
|---|---|---|
| macOS | Clash Verge Rev / Stash（付费） | 复制订阅 URL → Profiles → New |
| Windows | Clash Verge Rev / v2rayN | 同上 |
| iOS | Shadowrocket（$2.99） / Stash | 复制订阅 URL → 添加订阅 |
| Android | v2rayNG / Clash Meta for Android | 同上 |
| Linux | clash-verge-rev / sing-box | 同上 |
| 路由器 | OpenWrt + ShellCrash / PassWall2 | 同上 |

导入后开启 **"自动更新订阅"**，间隔设 1–6 小时。

## 九、新用户分发流程

每来一个新人：

1. 面板 → 入站 → 编辑 reality 入站 → **添加客户端** → 设邮箱 / UUID / 限流 / 到期日
2. 保存后，**操作 → 显示信息** → 复制**订阅链接**给新人
3. 新人粘贴到客户端就能用

**好处**：
- 每个人独立 UUID 和订阅链接，**单独限流量**、**单独设到期时间**、**单独看流量统计**
- 谁泄露了链接，单独禁用就行，不影响其他人

## 十、加固与运维

### 1. 给面板加 HTTPS（推荐但非必需）

裸 HTTP 面板登录密码会明文传输。如果你介意，可以在 **面板设置 → 证书** 里上传 Let's Encrypt 证书（用 acme.sh 申请，需要一个域名）。

如果懒得搞，**最简单的做法是只在使用时通过 SSH 隧道访问面板**：

```bash
# 本地终端跑这条，把远程面板端口转发到本地
ssh -L 52718:127.0.0.1:52718 -p 22000 root@你的IP

# 然后浏览器访问 http://127.0.0.1:52718/xj9k2lm/
```

再把 ufw 里的面板端口删掉，公网就完全访问不到面板，安全性最高。

### 2. 防 BT 滥用

3x-ui 默认已经在路由规则里 block bittorrent，验证一下：
入站列表 → 编辑 → 路由设置 → 确保 `blocked` 出站包含 `protocol: bittorrent`。

### 3. 流量监控
面板首页直接看实时流量、CPU、内存、节点流量排行。

### 4. 备份
```bash
# 数据库就一个文件
cp /etc/x-ui/x-ui.db ~/x-ui-backup-$(date +%F).db
```
建议每周自动 rsync 到另一台机器。

### 5. 被封了怎么办

- **症状**：443 端口 ping 通但握手失败 / 客户端连接超时
- **应对**：
  1. Vultr 后台**销毁机器（destroy）→ 重新部署**，会换新 IP（成本：几小时停服）
  2. 用备份的 `x-ui.db` 恢复，所有用户/节点配置秒回
  3. 把新 IP 通知用户即可（或者一开始就用一个解析到 VPS 的域名，换 IP 时只改 A 记录）

### 6. 别做的事

- ❌ 不要把面板默认端口暴露到 0.0.0.0
- ❌ 不要用国内手机号 / 支付宝绑定的邮箱注册 VPS
- ❌ 不要在节点上跑 BT / 爬虫 / 大规模扫描，会让整个 IP 段被拉黑
- ❌ 不要给陌生人共享 root 账号，分流量包给他用就行

## 参考资料

- 3x-ui 项目：https://github.com/MHSanaei/3x-ui
- Xray-core：https://github.com/XTLS/Xray-core
- Clash Verge Rev：https://github.com/clash-verge-rev/clash-verge-rev
- Reality 协议解读：https://github.com/XTLS/REALITY
