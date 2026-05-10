## 写在前面

2026 年抗封锁性最强的方案：**VLESS + Reality + 3x-ui 面板**。只需一台裸 IP VPS，不需要域名、证书、Cloudflare。

**Reality 的核心优势**：借用 microsoft.com / apple.com 等大站做 TLS 握手，GFW 主动探测看到的是真实大站证书，没法区分真假。

> 🎁 **VPS 推荐**：本文全程在 Vultr 大阪机房实测，按小时计费，IP 被封 destroy 重建只损失几小时。
> 走这条 [Vultr 邀请链接](https://www.vultr.com/?ref=9893559) 注册，新用户能拿到额度，对我也有少量返利，互相帮忙。

## 一、协议与面板选型

| 协议 | 抗封锁 | 现状 |
|---|---|---|
| Shadowsocks / SSR / 裸 VMess | ⭐⭐ | 特征明显，节日必死 |
| VMess + WS + TLS + CF | ⭐⭐⭐ | 还能用，CF IP 经常被限速 |
| Trojan / Trojan-Go | ⭐⭐⭐ | 需要域名+证书 |
| Hysteria2 / TUIC v5 | ⭐⭐⭐⭐ | 极快但 UDP 易被 QoS |
| **VLESS + Reality** | ⭐⭐⭐⭐⭐ | **当前最优解** |

**结论**：首选 VLESS + Reality，备用 Hysteria2。文末会顺手导出 SS 节点做兼容（老路由器用），日常用不到。

**面板**：3x-ui（社区最活跃，原生支持 Reality / Hysteria2 / TUIC，自带订阅 + Telegram Bot）。其它选项：Marzban（企业级）、Hiddify（一键脚本最完善）、sing-box 裸装（新手别碰）。

## 二、VPS 选购

| 机房 | 评价 |
|---|---|
| **Vultr 东京/大阪** | 推荐。$6/月，按小时计费，IP 被封 destroy 重建只损失几小时 |
| DigitalOcean | 稳定 $4/月，中国线路一般 |
| 搬瓦工 CN2 GIA | 国内直连最快，但 $10+/月，IP 难换 |
| Oracle Always Free | 永久免费，但申请门槛高、IP 经常被封 |

**要点**：日韩 > 美西 > 欧洲；≥1Gbps 端口、≥1TB/月；独立 IPv4；Ubuntu 22.04 或 Debian 12。

## 三、懒人模式：丢给 AI 自动搭建

整个搭建过程**只剩"买 VPS"是人工**。买完后把 SSH 凭据丢给 Claude Code / Cursor，加上下面这段提示词：

```text
我有一台全新的 Ubuntu 22.04 / Debian 12 VPS，凭据：
  IP: x.x.x.x   user: root   password: xxxxxxxx

请 SSH 上去**全程非交互**搭建。主力客户端 Clash Verge Rev (macOS) +
Shadowrocket (iOS)，核心交付物是一份 **Clash YAML 订阅 URL**。

──────────────────────────────────
1) 基础加固
──────────────────────────────────
- 时区 Asia/Shanghai
- 开启 BBR (net.core.default_qdisc=fq + tcp_congestion_control=bbr)
- 安装 ufw，默认 deny incoming，只放行：
    新 SSH 端口、80/tcp、443/tcp+udp、面板端口、2096/tcp、8388/tcp+udp
- SSH 端口改成随机 10000-65000：先在 ufw 加新端口规则，验证新端口
  可登录后再删 22 的允许规则（顺序错了会把自己锁外面）

──────────────────────────────────
2) 安装 3x-ui (https://github.com/MHSanaei/3x-ui)
──────────────────────────────────
⚠️ 官方 install.sh 末尾**强制**让你配 SSL、stdin 喂空也跳不过。
   必须先下下来 patch：

   curl -fsSL https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o install.sh
   sed -i 's|prompt_and_setup_ssl |: prompt_and_setup_ssl_disabled |g' install.sh
   sed -i 's|read -rp "Would you like to customize the Panel Port settings.*|config_confirm="n"|' install.sh
   bash install.sh < /dev/null

装完用 x-ui setting 覆盖账密：
   /usr/local/x-ui/x-ui setting \
       -username <随机10位> -password <强密码24位> \
       -port <随机10000-65000> -webBasePath <随机16位字母数字>
   systemctl restart x-ui

──────────────────────────────────
3) 创建入站（systemctl stop x-ui 后改 SQLite /etc/x-ui/x-ui.db）
──────────────────────────────────
**两个 client 共用同一个 subId**（一份订阅拿到两个节点）。
先生成共用 subId = openssl rand -hex 12

A. VLESS + Reality
   - 端口 443，listen 留空
   - flow: xtls-rprx-vision
   - dest: www.microsoft.com:443 / serverNames: ["www.microsoft.com"]
   - privateKey/publicKey 必须用 /usr/local/x-ui/bin/xray x25519 生成
     （不是 openssl）
   - shortIds: [openssl rand -hex 8]
   - sniffing: enabled, destOverride: [http,tls,quic,fakedns]
   - client: email=main, id=uuidgen, subId=<共用 subId>

B. Shadowsocks-2022
   - 端口 8388, method: 2022-blake3-aes-256-gcm
   - server PSK = openssl rand -base64 32
   - client PSK = openssl rand -base64 32
   - client: email=main-ss, subId=<同一个共用 subId>

改完 systemctl start x-ui，ss -tlnp 验证 :443 和 :8388 都在监听

──────────────────────────────────
4) 启用订阅服务（写入 settings 表）
──────────────────────────────────
subEnable=true / subPort=2096 / subPath=/sub/ / subJsonPath=/json/
subJsonEnable=true / subEncrypt=true / subTitle=<节点标题>

重启 x-ui，curl http://127.0.0.1:2096/sub/<subId> 应返回 200 + base64

──────────────────────────────────
5) 自建 Clash YAML 订阅（核心交付物）
──────────────────────────────────
⚠️ Clash 系客户端**不识别** base64 v2ray 订阅，导入会报
   `the remote profile data is invalid yaml`，必须自建 YAML。

- apt install -y nginx
- YAML 写到 /var/www/clash/<随机12位hex>.yaml
- nginx site 配置：
    location ~ ^/clash/[a-zA-Z0-9]+\.yaml$ {
        default_type 'application/x-yaml; charset=utf-8';
        try_files $uri =404;
    }
- 用 curl -I 验证返回 200 + Content-Type: application/x-yaml

YAML 必须包含：
- mode: rule，DNS fake-ip（国内 alidns/doh.pub，海外 fallback 1.1.1.1/8.8.8.8）
- proxies: VLESS-Reality + SS-2022（SS 的 password 写成
    "<server_psk>:<client_psk>"）
- proxy-groups: 🚀 PROXY(select) / ♻️ AUTO(url-test, 300s) /
    🍎 Apple / Ⓜ️ Microsoft / 🤖 OpenAI / 📲 Telegram /
    🛑 AdBlock(REJECT) / 🐟 FINAL
- rule-providers（每天自动更新）：
    Loyalsoldier/clash-rules → reject/icloud/apple/google/proxy/direct/
        private/gfw/tld-not-cn/telegramcidr/cncidr/lancidr/applications
    blackmatrix7/ios_rule_script → OpenAI、Microsoft
- rules 顺序：
    applications → private+lancidr → reject →
    openai/microsoft/icloud/apple/telegramcidr →
    google/gfw/tld-not-cn/proxy → direct/cncidr →
    GEOIP,CN,DIRECT → MATCH,🐟 FINAL

──────────────────────────────────
6) 输出交付清单（markdown）
──────────────────────────────────
**服务器**：新 SSH 端口 + 完整 ssh 命令、面板 URL/账密
**订阅**：
- 🖥 Clash Verge / Mihomo / Stash → http://IP/clash/xxxx.yaml（主力）
- 📱 Shadowrocket / v2rayN / NekoBox → http://IP:2096/sub/<subId>
- 🧪 sing-box / Clash.Meta JSON → http://IP:2096/json/<subId>
**单节点备用**：vless:// 链接、ss:// 链接（userinfo 是
   base64(method:server_psk:client_psk)）、二维码（qrencode -t ansiutf8）

──────────────────────────────────
注意事项
──────────────────────────────────
- 全程非交互：apt -y、ssh -o StrictHostKeyChecking=no、stdin 喂 < /dev/null
- 改 /etc/x-ui/x-ui.db 之前先 systemctl stop x-ui，改完再 start
- Reality 公私钥必须用 /usr/local/x-ui/bin/xray x25519，不是 openssl
- 两条入站的 client 必须用同一个 subId
- ufw 改 SSH 端口前先放行新端口并实测能登录，再删 22
- 凭据/密钥**只在最后交付清单**集中给出，过程中不要重复打印
- 任何步骤失败直接停下来报错，不要假装成功继续走
- 完成后**主动测**：
    1) curl 主面板 URL 返回 200/302
    2) curl 订阅 YAML 返回 200 + 正确 Content-Type
    3) openssl s_client -connect IP:443 -servername www.microsoft.com
       能拿到真实 microsoft 证书（验证 Reality 伪装 OK）
```

AI 跑完后拿到订阅链接，粘到 Clash Verge / Shadowrocket 即可。从 SSH 到能上网约 **5–10 分钟**。

下面是给"想搞清楚每一步"的读者的图文版。

## 四、手动搭建：基础加固

```bash
apt update && apt upgrade -y
timedatectl set-timezone Asia/Shanghai
apt install -y curl wget vim ufw socat

# SSH 改端口（挡 90% 暴力破解）
sed -i 's/#Port 22/Port 22000/' /etc/ssh/sshd_config
systemctl restart ssh

# 防火墙
ufw allow 22000/tcp && ufw allow 443/tcp && ufw allow 80/tcp
ufw --force enable

# BBR
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
sysctl net.ipv4.tcp_congestion_control   # 应输出 bbr
```

## 五、安装 3x-ui

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
```

安装时会问账号密码、面板端口、Web Path。**别用默认 2053 + 默认路径**，会被批量扫描。建议端口随机 10000–65000，路径随机字母数字。装完截图保存登录信息，并 `ufw allow <面板端口>/tcp`。

忘了凭据用 `x-ui settings` 查看，`x-ui` 进管理菜单。

## 六、创建 VLESS Reality 入站

浏览器打开 `http://IP:端口/路径/` 登录面板。**入站列表 → 添加入站**：

| 字段 | 值 |
|---|---|
| 协议 | VLESS |
| 端口 | 443 |
| 流控 (Flow) | `xtls-rprx-vision` |
| ID | 点按钮生成 UUID |
| Network | tcp |
| Security | **Reality** |
| uTLS | chrome |
| Dest | `www.microsoft.com:443`（同区域延迟低的大站，日机选 microsoft/apple，美机加 tesla） |
| Server Names | 与 Dest 同名 |
| 私钥/公钥 | 点"获取新证书"自动生成 |
| Short Ids | 点"生成"自动生成 |

可选：再加一条 Hysteria2 兜底，UDP 端口（如 36712），别忘 `ufw allow 36712/udp`。

## 七、订阅服务

**面板设置 → 订阅设置**：启用 ✅ / 端口 2096 / 路径 `/sub/` / JSON 路径 `/json/`，保存后 `x-ui restart` 并 `ufw allow 2096/tcp`。

回入站列表 → **操作 → 显示信息**，能看到：
- 二维码、`vless://` 单节点链接
- **普通订阅**：`http://IP:2096/sub/<subId>`（v2rayN / Shadowrocket / NekoBox 原生支持）
- **JSON 订阅**：`http://IP:2096/json/<subId>`（sing-box / Clash.Meta）

### Clash 订阅必须自建 YAML

3x-ui 不直接生成 Clash YAML，base64 订阅 **Clash Verge / Stash / Mihomo Party 都不认**，会报 `the remote profile data is invalid yaml`。三种方案：

- **A. 在线 subconverter**：依赖第三方，节点信息会过他们服务器，经常被滥用限流。
- **B. 自建 subconverter（docker）**：要装 docker、配模板，杀鸡用牛刀。
- **C. nginx 托管手写 YAML（强烈推荐）**：不依赖外部、零失败风险，节点不变就一直能用，要改 ssh 上去改 YAML 即可。

**方案 C 操作**：

```bash
apt install -y nginx
ufw allow 80/tcp

RAND=$(openssl rand -hex 12)
mkdir -p /var/www/clash
cat > /var/www/clash/${RAND}.yaml <<'YAML'
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
ipv6: false

dns:
  enable: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query

proxies:
  - name: "🇯🇵 VPS-VLESS-Reality"
    type: vless
    server: <你的IP>
    port: 443
    uuid: <面板里的UUID>
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: www.microsoft.com
    client-fingerprint: chrome
    reality-opts:
      public-key: <面板里的Public Key>
      short-id: <面板里的Short ID>

  - name: "🇯🇵 VPS-SS2022"
    type: ss
    server: <你的IP>
    port: 8388
    cipher: 2022-blake3-aes-256-gcm
    password: "<server_psk>:<client_psk>"
    udp: true

proxy-groups:
  - { name: "🚀 PROXY", type: select, proxies: ["♻️ AUTO", "🇯🇵 VPS-VLESS-Reality", "🇯🇵 VPS-SS2022", DIRECT] }
  - { name: "♻️ AUTO", type: url-test, url: http://www.gstatic.com/generate_204, interval: 300, tolerance: 50, proxies: ["🇯🇵 VPS-VLESS-Reality", "🇯🇵 VPS-SS2022"] }
  - { name: "🍎 Apple",     type: select, proxies: [DIRECT, "🚀 PROXY"] }
  - { name: "Ⓜ️ Microsoft", type: select, proxies: [DIRECT, "🚀 PROXY"] }
  - { name: "🤖 OpenAI",    type: select, proxies: ["🚀 PROXY", DIRECT] }
  - { name: "📲 Telegram",  type: select, proxies: ["🚀 PROXY", DIRECT] }
  - { name: "🛑 AdBlock",   type: select, proxies: [REJECT, DIRECT] }
  - { name: "🐟 FINAL",     type: select, proxies: ["🚀 PROXY", DIRECT] }

# 规则集来源：Loyalsoldier/clash-rules + blackmatrix7/ios_rule_script
# (此处 13 个 rule-provider 项见原仓库，每天 86400s 自动更新)
rule-providers:
  reject:       { type: http, behavior: domain,    format: text, interval: 86400, path: ./ruleset/reject.txt,       url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/reject.txt }
  icloud:       { type: http, behavior: domain,    format: text, interval: 86400, path: ./ruleset/icloud.txt,       url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/icloud.txt }
  apple:        { type: http, behavior: domain,    format: text, interval: 86400, path: ./ruleset/apple.txt,        url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/apple.txt }
  google:       { type: http, behavior: domain,    format: text, interval: 86400, path: ./ruleset/google.txt,       url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/google.txt }
  proxy:        { type: http, behavior: domain,    format: text, interval: 86400, path: ./ruleset/proxy.txt,        url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/proxy.txt }
  direct:       { type: http, behavior: domain,    format: text, interval: 86400, path: ./ruleset/direct.txt,       url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt }
  private:      { type: http, behavior: domain,    format: text, interval: 86400, path: ./ruleset/private.txt,      url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/private.txt }
  gfw:          { type: http, behavior: domain,    format: text, interval: 86400, path: ./ruleset/gfw.txt,          url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/gfw.txt }
  tld-not-cn:   { type: http, behavior: domain,    format: text, interval: 86400, path: ./ruleset/tld-not-cn.txt,   url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/tld-not-cn.txt }
  telegramcidr: { type: http, behavior: ipcidr,    format: text, interval: 86400, path: ./ruleset/telegramcidr.txt, url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/telegramcidr.txt }
  cncidr:       { type: http, behavior: ipcidr,    format: text, interval: 86400, path: ./ruleset/cncidr.txt,       url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/cncidr.txt }
  lancidr:      { type: http, behavior: ipcidr,    format: text, interval: 86400, path: ./ruleset/lancidr.txt,      url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/lancidr.txt }
  applications: { type: http, behavior: classical, format: text, interval: 86400, path: ./ruleset/applications.txt, url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/applications.txt }
  openai:       { type: http, behavior: classical, format: text, interval: 86400, path: ./ruleset/openai.txt,       url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/OpenAI/OpenAI.list }
  microsoft:    { type: http, behavior: classical, format: text, interval: 86400, path: ./ruleset/microsoft.txt,    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Microsoft/Microsoft.list }

rules:
  - RULE-SET,applications,DIRECT
  - RULE-SET,private,DIRECT
  - RULE-SET,lancidr,DIRECT,no-resolve
  - RULE-SET,reject,🛑 AdBlock
  - RULE-SET,openai,🤖 OpenAI
  - RULE-SET,microsoft,Ⓜ️ Microsoft
  - RULE-SET,icloud,🍎 Apple
  - RULE-SET,apple,🍎 Apple
  - RULE-SET,telegramcidr,📲 Telegram,no-resolve
  - RULE-SET,google,🚀 PROXY
  - RULE-SET,gfw,🚀 PROXY
  - RULE-SET,tld-not-cn,🚀 PROXY
  - RULE-SET,proxy,🚀 PROXY
  - RULE-SET,direct,DIRECT
  - RULE-SET,cncidr,DIRECT,no-resolve
  - GEOIP,CN,DIRECT
  - MATCH,🐟 FINAL
YAML

# nginx：必须返回 application/x-yaml，否则 Clash 按 text/plain 处理会报错
cat > /etc/nginx/sites-available/clash-sub <<'NGX'
server {
    listen 80;
    root /var/www;
    location ~ ^/clash/[a-zA-Z0-9]+\.yaml$ {
        default_type 'application/x-yaml; charset=utf-8';
        try_files $uri =404;
    }
    location / { return 404; }
}
NGX
ln -sf /etc/nginx/sites-available/clash-sub /etc/nginx/sites-enabled/clash-sub
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

echo "http://你的IP/clash/${RAND}.yaml"
```

> SS-2022 的 `password` 字段格式 `<server_psk>:<client_psk>`，server_psk 是入站设置里的"密码"，client_psk 是客户端那栏的"密码"，都是 32 字节 base64。老 cipher（chacha20 等）只填一段密码即可。

### Shadowsocks 节点（兼容用）

入站列表 → 添加入站 → 协议 Shadowsocks，端口 8388，加密 `2022-blake3-aes-256-gcm`，密码自动生成。保存后订阅链接里就会包含 `ss://`。**仅在客户端不支持 VLESS 时用**。

## 八、客户端

| 平台 | 推荐客户端 |
|---|---|
| macOS / Windows / Linux | Clash Verge Rev / Stash |
| iOS | Shadowrocket（$2.99） |
| Android | v2rayNG / Clash Meta for Android |
| 路由器 | OpenWrt + ShellCrash / PassWall2 |

复制订阅 URL → 添加订阅 → 开启**自动更新**（间隔 1–6 小时）。

## 九、新用户分发

每来一个新人：入站 → 编辑 reality 入站 → **添加客户端** → 设邮箱/UUID/限流/到期日 → **操作 → 显示信息** → 把订阅链接给他。每人独立 UUID 和订阅，**单独限流量、单独到期、单独看流量**；谁泄露单独禁用。

## 十、加固与运维

**面板加 HTTPS**：最简单的做法是别公开面板，用 SSH 隧道访问：

```bash
ssh -L 52718:127.0.0.1:52718 -p 22000 root@你的IP
# 浏览器访问 http://127.0.0.1:52718/路径/
```

然后 `ufw delete` 删掉公网面板端口规则，安全性最高。

**防 BT 滥用**：3x-ui 默认已 block，验证一下 → 入站 → 路由设置 → `blocked` 出站含 `protocol: bittorrent`。

**备份**：`cp /etc/x-ui/x-ui.db ~/x-ui-backup-$(date +%F).db`，建议每周 rsync 到另一台机器。

**被封了**（443 ping 通但握手失败）：Vultr 后台 destroy → 重新部署换新 IP（几小时停服）→ 用备份的 `x-ui.db` 恢复 → 通知用户新 IP（或一开始就用域名 A 记录指向 VPS）。

**别做的事**：
- ❌ 面板默认端口暴露公网
- ❌ 国内手机号/支付宝邮箱注册 VPS
- ❌ 在节点上跑 BT / 爬虫 / 大规模扫描
- ❌ 给陌生人共享 root，分流量包就行

## 参考

- 3x-ui: https://github.com/MHSanaei/3x-ui
- Xray-core: https://github.com/XTLS/Xray-core
- Clash Verge Rev: https://github.com/clash-verge-rev/clash-verge-rev
- Reality 协议: https://github.com/XTLS/REALITY
