## Foreword

The strongest anti-censorship setup in 2026: **VLESS + Reality + 3x-ui panel**. All you need is a bare-IP VPS — no domain, no certificate, no Cloudflare.

**Why Reality wins**: it borrows the TLS handshake of a major site like microsoft.com / apple.com. When the GFW probes you actively, it sees a real Microsoft certificate and cannot tell the difference.

> 🎁 **VPS recommendation**: this whole guide was tested end-to-end on Vultr's Osaka region — hourly billing, so if your IP ever gets blocked you can destroy and redeploy with only a few hours of downtime.
> If you sign up via this [Vultr referral link](https://www.vultr.com/?ref=9893559), you get free credit and I get a small kickback. Win-win.

## 1. Protocol and Panel Selection

| Protocol | Censorship resistance | Status |
|---|---|---|
| Shadowsocks / SSR / plain VMess | ⭐⭐ | Distinctive fingerprint, dies on every holiday |
| VMess + WS + TLS + CF | ⭐⭐⭐ | Still works, but CF IPs get throttled often |
| Trojan / Trojan-Go | ⭐⭐⭐ | Requires domain + cert |
| Hysteria2 / TUIC v5 | ⭐⭐⭐⭐ | Extremely fast, but UDP is easily QoS'd |
| **VLESS + Reality** | ⭐⭐⭐⭐⭐ | **The current best answer** |

**Bottom line**: prefer VLESS + Reality, with Hysteria2 as backup. We'll also export an SS node at the end for compatibility (legacy routers); you won't use it day-to-day.

**Panel**: 3x-ui (most active community, native support for Reality / Hysteria2 / TUIC, built-in subscription + Telegram bot). Alternatives: Marzban (enterprise-grade), Hiddify (most polished one-click installer), bare sing-box (don't go there as a beginner).

## 2. Choosing a VPS

| Provider | Notes |
|---|---|
| **Vultr Tokyo / Osaka** | Recommended. ~$6/mo, hourly billing, swap a blocked IP in hours by destroying & redeploying |
| DigitalOcean | Stable, ~$4/mo, but China routing is mediocre |
| BandwagonHost CN2 GIA | Best direct-to-China latency, but $10+/mo and the IP is hard to swap |
| Oracle Always Free | Free forever, but signup is painful and IPs get blocked frequently |

**Rules of thumb**: Japan/Korea > US West > Europe; ≥1 Gbps port, ≥1 TB/month; dedicated IPv4; Ubuntu 22.04 or Debian 12.

## 3. Lazy Mode: Let AI Build It

Buying the VPS is now the only manual step. Once you have SSH credentials, hand them to Claude Code / Cursor with this prompt:

```text
I have a brand-new Ubuntu 22.04 / Debian 12 VPS, credentials:
  IP: x.x.x.x   user: root   password: xxxxxxxx

SSH in and build everything **fully non-interactively**. My main clients are
Clash Verge Rev (macOS) + Shadowrocket (iOS). The core deliverable is a
**Clash YAML subscription URL**.

──────────────────────────────────
1) Baseline hardening
──────────────────────────────────
- Timezone Asia/Shanghai
- Enable BBR (net.core.default_qdisc=fq + tcp_congestion_control=bbr)
- Install ufw, default deny incoming, only allow:
    new SSH port, 80/tcp, 443/tcp+udp, panel port, 2096/tcp, 8388/tcp+udp
- Move SSH to a random 10000-65000 port: add the new port rule in ufw,
  verify you can log in on it, **then** drop the rule for 22 (wrong order
  locks you out).

──────────────────────────────────
2) Install 3x-ui (https://github.com/MHSanaei/3x-ui)
──────────────────────────────────
⚠️ The official install.sh **forces** an SSL prompt at the end; feeding empty
   stdin won't bypass it. You must download and patch first:

   curl -fsSL https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o install.sh
   sed -i 's|prompt_and_setup_ssl |: prompt_and_setup_ssl_disabled |g' install.sh
   sed -i 's|read -rp "Would you like to customize the Panel Port settings.*|config_confirm="n"|' install.sh
   bash install.sh < /dev/null

After installation, override credentials with `x-ui setting`:
   /usr/local/x-ui/x-ui setting \
       -username <random 10 chars> -password <strong 24 chars> \
       -port <random 10000-65000> -webBasePath <random 16 alphanum>
   systemctl restart x-ui

──────────────────────────────────
3) Create inbounds (systemctl stop x-ui, edit SQLite /etc/x-ui/x-ui.db)
──────────────────────────────────
**Both clients share the same subId** (one subscription delivers both nodes).
First generate the shared subId = openssl rand -hex 12

A. VLESS + Reality
   - Port 443, listen blank
   - flow: xtls-rprx-vision
   - dest: www.microsoft.com:443 / serverNames: ["www.microsoft.com"]
   - privateKey/publicKey **must** be generated with
     /usr/local/x-ui/bin/xray x25519 (not openssl)
   - shortIds: [openssl rand -hex 8]
   - sniffing: enabled, destOverride: [http,tls,quic,fakedns]
   - client: email=main, id=uuidgen, subId=<shared subId>

B. Shadowsocks-2022
   - Port 8388, method: 2022-blake3-aes-256-gcm
   - server PSK = openssl rand -base64 32
   - client PSK = openssl rand -base64 32
   - client: email=main-ss, subId=<same shared subId>

After editing, systemctl start x-ui, then `ss -tlnp` to confirm :443 and :8388
are both listening.

──────────────────────────────────
4) Enable subscription service (write the settings table)
──────────────────────────────────
subEnable=true / subPort=2096 / subPath=/sub/ / subJsonPath=/json/
subJsonEnable=true / subEncrypt=true / subTitle=<node title>

Restart x-ui. `curl http://127.0.0.1:2096/sub/<subId>` should return 200 + base64.

──────────────────────────────────
5) Self-hosted Clash YAML subscription (the core deliverable)
──────────────────────────────────
⚠️ Clash-family clients **do not** accept the base64 v2ray subscription;
   importing it errors with `the remote profile data is invalid yaml`.
   You must serve a hand-built YAML.

- apt install -y nginx
- Write the YAML to /var/www/clash/<random 12 hex>.yaml
- nginx site config:
    location ~ ^/clash/[a-zA-Z0-9]+\.yaml$ {
        default_type 'application/x-yaml; charset=utf-8';
        try_files $uri =404;
    }
- Verify with `curl -I` that it returns 200 + Content-Type: application/x-yaml

The YAML must contain:
- mode: rule, DNS fake-ip (CN: alidns/doh.pub, fallback: 1.1.1.1/8.8.8.8)
- proxies: VLESS-Reality + SS-2022 (the SS `password` is
    "<server_psk>:<client_psk>")
- proxy-groups: 🚀 PROXY(select) / ♻️ AUTO(url-test, 300s) /
    🍎 Apple / Ⓜ️ Microsoft / 🤖 OpenAI / 📲 Telegram /
    🛑 AdBlock(REJECT) / 🐟 FINAL
- rule-providers (auto-update daily):
    Loyalsoldier/clash-rules → reject/icloud/apple/google/proxy/direct/
        private/gfw/tld-not-cn/telegramcidr/cncidr/lancidr/applications
    blackmatrix7/ios_rule_script → OpenAI, Microsoft
- rules order:
    applications → private+lancidr → reject →
    openai/microsoft/icloud/apple/telegramcidr →
    google/gfw/tld-not-cn/proxy → direct/cncidr →
    GEOIP,CN,DIRECT → MATCH,🐟 FINAL

──────────────────────────────────
6) Final delivery checklist (markdown)
──────────────────────────────────
**Server**: new SSH port + complete ssh command, panel URL/credentials
**Subscription**:
- 🖥 Clash Verge / Mihomo / Stash → http://IP/clash/xxxx.yaml (primary)
- 📱 Shadowrocket / v2rayN / NekoBox → http://IP:2096/sub/<subId>
- 🧪 sing-box / Clash.Meta JSON → http://IP:2096/json/<subId>
**Single-node fallback**: vless:// link, ss:// link (userinfo is
   base64(method:server_psk:client_psk)), QR code (qrencode -t ansiutf8)

──────────────────────────────────
Constraints
──────────────────────────────────
- Fully non-interactive: apt -y, ssh -o StrictHostKeyChecking=no, stdin < /dev/null
- Always systemctl stop x-ui before editing /etc/x-ui/x-ui.db, then start
- Reality keypair MUST come from /usr/local/x-ui/bin/xray x25519, not openssl
- Both inbound clients MUST share the same subId
- Before changing the SSH port in ufw, allow the new port AND verify you can
  log in on it, only then drop 22
- Keep credentials/keys for the **final delivery checklist only**, don't
  echo them mid-run
- If any step fails, stop and surface the error — do not pretend success
- After completion, **actively verify**:
    1) curl the panel URL → 200/302
    2) curl the YAML subscription → 200 + correct Content-Type
    3) openssl s_client -connect IP:443 -servername www.microsoft.com
       returns the real Microsoft certificate (proves Reality camouflage works)
```

Once the AI finishes, paste the subscription link into Clash Verge / Shadowrocket. From SSH to working proxy: about **5–10 minutes**.

The rest of this guide is the illustrated walkthrough for readers who want to understand each step.

## 4. Manual Setup: Hardening

```bash
apt update && apt upgrade -y
timedatectl set-timezone Asia/Shanghai
apt install -y curl wget vim ufw socat

# Move SSH off the default port (blocks 90% of brute-force scanners)
sed -i 's/#Port 22/Port 22000/' /etc/ssh/sshd_config
systemctl restart ssh

# Firewall
ufw allow 22000/tcp && ufw allow 443/tcp && ufw allow 80/tcp
ufw --force enable

# BBR
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
sysctl net.ipv4.tcp_congestion_control   # should print "bbr"
```

## 5. Install 3x-ui

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
```

The installer asks for username/password, panel port, and web path. **Don't use the default 2053 + default path** — bots scan for them. Pick a random port in 10000–65000 and a random alphanumeric path. Save the login info, and `ufw allow <panel-port>/tcp`.

If you forget the credentials: `x-ui settings` to view them, `x-ui` for the management menu.

## 6. Create the VLESS Reality Inbound

Open `http://IP:port/path/` in a browser and log in. **Inbounds → Add Inbound**:

| Field | Value |
|---|---|
| Protocol | VLESS |
| Port | 443 |
| Flow | `xtls-rprx-vision` |
| ID | Click the button to generate a UUID |
| Network | tcp |
| Security | **Reality** |
| uTLS | chrome |
| Dest | `www.microsoft.com:443` (a low-latency major site in your region — pick microsoft/apple from Japan, add tesla from US) |
| Server Names | Same hostname as Dest |
| Private/Public Key | Click "Get New Cert" to auto-generate |
| Short Ids | Click "Generate" to auto-generate |

Optional: add a Hysteria2 inbound as backup on a UDP port (e.g. 36712) — don't forget `ufw allow 36712/udp`.

## 7. Subscription Service

**Panel Settings → Subscription Settings**: Enable ✅ / port 2096 / path `/sub/` / JSON path `/json/`. Save, run `x-ui restart`, then `ufw allow 2096/tcp`.

Back in the inbound list → **Actions → Show Info**, you'll see:

- QR code, single-node `vless://` link
- **Plain subscription**: `http://IP:2096/sub/<subId>` (natively supported by v2rayN / Shadowrocket / NekoBox)
- **JSON subscription**: `http://IP:2096/json/<subId>` (sing-box / Clash.Meta)

### Clash subscriptions require a hand-built YAML

3x-ui doesn't generate Clash YAML directly, and the base64 subscription is **rejected by Clash Verge / Stash / Mihomo Party** with `the remote profile data is invalid yaml`. Three options:

- **A. Online subconverter**: depends on a third party; your node info traverses their servers and they're frequently rate-limited or abused.
- **B. Self-hosted subconverter (Docker)**: requires Docker + template tuning — overkill.
- **C. nginx-served hand-built YAML (strongly recommended)**: zero external dependencies, zero failure modes, works as long as the nodes don't change. To edit, just SSH in and edit the YAML.

**Option C — execute on the server**:

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
    server: <YOUR_IP>
    port: 443
    uuid: <UUID_FROM_PANEL>
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: www.microsoft.com
    client-fingerprint: chrome
    reality-opts:
      public-key: <PUBLIC_KEY_FROM_PANEL>
      short-id: <SHORT_ID_FROM_PANEL>

  - name: "🇯🇵 VPS-SS2022"
    type: ss
    server: <YOUR_IP>
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

# Rule sources: Loyalsoldier/clash-rules + blackmatrix7/ios_rule_script
# (13 rule-provider entries, auto-refresh every 86400s)
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

# nginx: must return application/x-yaml — Clash chokes on text/plain
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

echo "http://YOUR_IP/clash/${RAND}.yaml"
```

> The SS-2022 `password` field is `<server_psk>:<client_psk>`. The server PSK is the "Password" on the inbound itself; the client PSK is the "Password" in the client row. Both are 32-byte base64. Older ciphers (chacha20 etc.) take a single password.

### Shadowsocks node (compatibility)

Inbounds → Add Inbound → protocol Shadowsocks, port 8388, cipher `2022-blake3-aes-256-gcm`, auto-generate the password. Once saved, the subscription will include an `ss://` entry. **Use only when a client doesn't support VLESS.**

## 8. Clients

| Platform | Recommended client |
|---|---|
| macOS / Windows / Linux | Clash Verge Rev / Stash |
| iOS | Shadowrocket ($2.99) |
| Android | v2rayNG / Clash Meta for Android |
| Routers | OpenWrt + ShellCrash / PassWall2 |

Copy the subscription URL → add subscription → enable **auto-update** (every 1–6 hours).

## 9. Onboarding New Users

For each new person: Inbound → edit the Reality inbound → **Add Client** → set email/UUID/quota/expiry → **Actions → Show Info** → hand them the subscription link. Each user gets their own UUID and subscription, with **per-user quota, per-user expiry, per-user traffic stats**. If anyone leaks their link, disable just that user.

## 10. Hardening and Operations

**Putting HTTPS on the panel**: the simplest answer is to not expose the panel publicly at all — reach it through an SSH tunnel:

```bash
ssh -L 52718:127.0.0.1:52718 -p 22000 root@YOUR_IP
# Then browse http://127.0.0.1:52718/path/
```

After that, `ufw delete` the public panel rule. Highest security with the least effort.

**Block BT abuse**: 3x-ui blocks it by default — verify in Inbound → Routing Settings → the `blocked` outbound contains `protocol: bittorrent`.

**Backups**: `cp /etc/x-ui/x-ui.db ~/x-ui-backup-$(date +%F).db`. Rsync this to another machine weekly.

**When you get blocked** (port 443 pings but TLS handshake fails): destroy the VPS in Vultr's dashboard → redeploy on a fresh IP (a few hours of downtime) → restore the backed-up `x-ui.db` → notify users of the new IP (or, from day one, point a DNS A record at the VPS so you only have to change DNS).

**Don't**:
- ❌ Expose the panel on the default port to the public internet
- ❌ Sign up for the VPS with a Chinese phone number / Alipay email
- ❌ Run BT / scrapers / mass scans through the node
- ❌ Share root with strangers — give them a traffic quota instead

## References

- 3x-ui: https://github.com/MHSanaei/3x-ui
- Xray-core: https://github.com/XTLS/Xray-core
- Clash Verge Rev: https://github.com/clash-verge-rev/clash-verge-rev
- Reality protocol: https://github.com/XTLS/REALITY
