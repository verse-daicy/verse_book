#!/usr/bin/env bash
# ============================================================
# Verse 羁绊书境 v1.0 一键部署脚本（Spring Boot + MySQL）
# 用法（在服务器上，先上传并解压两个分卷 zip 到 /root/sylvia/）：
#   unzip -o Sylvia-demo-v1.0-part1-jar.zip
#   unzip -o Sylvia-demo-v1.0-part2-public.zip
#   sudo bash /root/sylvia/Sylvia-demo-v1.0/sylvia-server/deploy.sh
#
# 第一个参数（可选）支持两种写法：
#   - 服务目录： /root/sylvia/Sylvia-demo-v1.0/sylvia-server
#   - zip 文件： /root/sylvia/Sylvia-demo-v1.0.zip（脚本自动解压到 /root/sylvia/）
#
# 特点：
#   - 完整版（非增量）：jar + 全部静态资源一次到位
#   - 自动备份现有服务（public + jar + .env）到 /root/sylvia/backup-<时间戳>/
#   - 自动停旧版 sylvia-4.0/4.1/4.2/4.3（释放 3000 端口），nginx 80 反代无需改动
#   - 数据库不动（线上库已是最终版 25 本）
# ============================================================
set -euo pipefail

# ---------- 可配置项 ----------
ARG="${1:-}"                                        # 目录或 zip，空则用默认目录
SRV_DIR_DEFAULT="/root/sylvia/Sylvia-demo-v1.0/sylvia-server"
ZIP_ROOT="/root/sylvia"                             # zip 解压根目录
APP_ROOT="/root/sylvia/Sylvia-demo-1.0"            # 部署根目录
APP_DIR="${APP_ROOT}/sylvia-server"                # 服务目录（含 jar + public）
SERVICE="sylvia-demo-1.0"                          # systemd 服务名
JAR_NAME="sylvia-demo-1.0.jar"
PORT="${PORT:-3000}"
DOMAIN="${DOMAIN:-mist-mo.top}"
JAVA_MAJOR=17
TS="$(date +%Y%m%d%H%M%S)"
BK="/root/sylvia/backup-${TS}"

# ---------- 颜色输出 ----------
c_green='\033[0;32m'; c_yellow='\033[1;33m'; c_red='\033[0;31m'; c_reset='\033[0m'
info()  { echo -e "${c_green}✔${c_reset} $*"; }
warn()  { echo -e "${c_yellow}⚠${c_reset} $*"; }
err()   { echo -e "${c_red}✘${c_reset} $*" >&2; }

# ---------- 解析第一个参数：目录 or zip ----------
if [ -n "$ARG" ]; then
  if [ -d "$ARG" ]; then
    SRV_DIR="$ARG"
  elif [ -f "$ARG" ] && [[ "$ARG" == *.zip ]]; then
    warn "参数是 zip 文件，自动解压到 ${ZIP_ROOT} …"
    mkdir -p "$ZIP_ROOT"
    unzip -o "$ARG" -d "$ZIP_ROOT" >/dev/null
    SRV_DIR="${ZIP_ROOT}/Sylvia-demo-v1.0/sylvia-server"
  else
    err "参数既不是目录也不是 zip 文件：$ARG"
    exit 1
  fi
else
  SRV_DIR="$SRV_DIR_DEFAULT"
fi

echo ""
echo "==============================================="
echo "  📚 Verse 羁绊书境 v1.0 一键部署（完整版）"
echo "==============================================="
echo "  源目录   : ${SRV_DIR}"
echo "  部署目录 : ${APP_DIR}"
echo "  服务     : ${SERVICE}"
echo "  端口     : ${PORT}"
echo "  域名     : ${DOMAIN}"
echo "-----------------------------------------------"

# ---------- 0. root 检查 ----------
[ "$(id -u)" -eq 0 ] || { err "请用 root 运行：sudo bash deploy.sh"; exit 1; }

# ---------- 1. Java 17 检查/安装 ----------
if ! command -v java >/dev/null 2>&1 || [ "$(java -version 2>&1 | grep -oP 'version \"\K[0-9]+' | head -1)" -lt "$JAVA_MAJOR" ]; then
  warn "未检测到 Java ≥ ${JAVA_MAJOR}，开始安装 openjdk-17-jre-headless …"
  apt-get update -qq && apt-get install -y openjdk-17-jre-headless
fi
JAVA_BIN="$(command -v java)"
info "Java：$(java -version 2>&1 | head -1)"

# ---------- 2. 源目录校验 ----------
SRV="$SRV_DIR"
[ -d "$SRV" ] || { err "找不到服务目录：$SRV（请先上传并解压两个 zip：part1-jar + part2-public）"; exit 1; }
[ -f "$SRV/$JAR_NAME" ] || { err "未找到 $JAR_NAME"; exit 1; }
[ -f "$SRV/public/index.html" ] || { err "未找到 public/index.html"; exit 1; }
info "包内容校验通过（jar + public/index.html）"

# ---------- 3. 备份现有服务 ----------
info "备份现有服务 → ${BK}"
mkdir -p "$BK"
if [ -d "/root/sylvia/Sylvia-4.3/sylvia-server" ]; then
  cp -r /root/sylvia/Sylvia-4.3/sylvia-server/public "$BK/public-v4.3" 2>/dev/null || true
  cp /root/sylvia/Sylvia-4.3/sylvia-server/sylvia-4.3.jar "$BK/" 2>/dev/null || true
  cp /root/sylvia/Sylvia-4.3/sylvia-server/.env "$BK/.env-v4.3" 2>/dev/null || true
  info "  已备份 v4.3（public + jar + .env）"
fi
if [ -d "$APP_DIR" ]; then
  cp -r "$APP_DIR/public" "$BK/public-current" 2>/dev/null || true
  cp "$APP_DIR/$JAR_NAME" "$BK/" 2>/dev/null || true
  info "  已备份当前 ${APP_DIR}"
fi
ls "$BK" >/dev/null 2>&1 && info "备份完成：$(ls "$BK" | tr '\n' ' ')"

# ---------- 4. 停止旧服务释放端口 ----------
info "停止旧版服务（释放 ${PORT} 端口）…"
for svc in sylvia-4.3 sylvia-4.2 sylvia-4.1 sylvia-4.0 sylvia "$SERVICE"; do
  if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service" || [ -f "/etc/systemd/system/${svc}.service" ]; then
    systemctl stop "$svc" >/dev/null 2>&1 || true
    systemctl disable "$svc" >/dev/null 2>&1 || true
    info "  已停止 ${svc}"
  fi
done
pm2 delete sylvia >/dev/null 2>&1 || true
pm2 delete sylvia-4.0 >/dev/null 2>&1 || true
if command -v ss >/dev/null 2>&1 && ss -ltn | grep -q ":${PORT} "; then
  warn "端口 ${PORT} 仍被占用，强制释放…"
  fuser -k "${PORT}/tcp" >/dev/null 2>&1 || true
  sleep 2
fi

# ---------- 5. 安装 jar + 静态资源 ----------
# ---------- 5. 安装 jar + 静态资源 ----------
info "安装到 ${APP_DIR} …"
mkdir -p "$APP_DIR"
cp -f "$SRV/$JAR_NAME" "$APP_DIR/"
rm -rf "$APP_DIR/public"
cp -r "$SRV/public" "$APP_DIR/public"

# ==========================================
# ★ 自动注入 Verse 的 UI 样式和替换文字 ★
# ==========================================
info "正在修改前端界面（替换 Logo、竖向排版、背景变色）..."
IDX_FILE="$APP_DIR/public/index.html"

# 1. 将 HTML 里的 Sylvia 替换为 Verse
sed -i 's/Sylvia/Verse/g' "$IDX_FILE"

# 2. 注入全新的样式和替换脚本（插在 </head> 前面）
INJECT_CONTENT='<style>
/* 强制竖向排版 */
[class*="scroll"], [class*="shelf"], .book-container {
    display: flex !important;
    flex-direction: column !important;
    overflow-x: hidden !important;
    overflow-y: auto !important;
    height: auto !important;
    gap: 20px !important;
}
.book-card, [class*="card"] {
    width: 90% !important;
    max-width: 600px !important;
    margin: 0 auto !important;
}
/* 粉蓝渐变加黄色晕染背景 */
body, html, #app {
    background: 
        radial-gradient(circle at 15% 50%, rgba(255, 223, 0, 0.4) 0%, transparent 40%),
        radial-gradient(circle at 85% 30%, rgba(255, 182, 193, 0.6) 0%, transparent 50%),
        radial-gradient(circle at 50% 80%, rgba(135, 206, 235, 0.6) 0%, transparent 50%),
        linear-gradient(135deg, #fce4ec 0%, #e3f2fd 100%) !important;
    background-attachment: fixed !important;
    min-height: 100vh;
}
/* 强制把文字变成深色，否则看不清 */
body, p, span, div, h1, h2, h3, h4, h5, h6 { color: #333333 !important; }
[class*="title"], [class*="logo"] { color: #d81b60 !important; text-shadow: none !important; }
</style>
<script>
/* 双重保险：等页面渲染完，强行把文本里的 Sylvia 换成 Verse */
window.addEventListener("DOMContentLoaded", () => {
    setTimeout(() => {
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        let node;
        while (node = walker.nextNode()) {
            if (node.nodeValue && node.nodeValue.includes("Sylvia")) {
                node.nodeValue = node.nodeValue.replace(/Sylvia/g, "Verse");
            }
        }
    }, 500);
});
</script>
</head>'

# 将上面的内容替换掉原本的 </head>
sed -i "s|</head>|$INJECT_CONTENT|" "$IDX_FILE"

# 清理旧的后端缓存（不删包，只刷新）
rm -rf "$APP_DIR/public/assets.bak" 2>/dev/null || true
info "前端 UI 自动修改完成！"
# ==========================================

# voices.json：缺失时显式告警
if [ -f "$SRV/voices.json" ]; then
  cp -f "$SRV/voices.json" "$APP_DIR/"
  info "  voices.json 已安装"
else
  warn "  未找到 voices.json，TTS 音色库将缺失（念书功能可能异常）"
fi

# .env：优先沿用旧 v4.3 → 模板 → 空文件兜底
if [ ! -f "$APP_DIR/.env" ]; then
  if [ -f "/root/sylvia/Sylvia-4.3/sylvia-server/.env" ]; then
    cp /root/sylvia/Sylvia-4.3/sylvia-server/.env "$APP_DIR/.env"
    info "  已从 v4.3 沿用 .env（TTS/ARK/JWT 配置保留）"
  elif [ -f "$SRV/.env.example" ]; then
    cp -f "$SRV/.env.example" "$APP_DIR/.env"
    warn "  未找到旧 .env，已用 .env.example 模板生成（请按需填 TTS/ARK key）"
  else
    : > "$APP_DIR/.env"
    warn "  未找到 .env 模板，已生成空 .env（TTS/ARK 将降级为 503）"
  fi
else
  info "  .env 已存在，保留不动"
fi
info "jar + public + voices.json + .env 就位"

# ---------- 6. systemd 服务 ----------
SERVICE_FILE="/etc/systemd/system/${SERVICE}.service"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Sylvia Forest Bookhouse v1.0 (Spring Boot)
After=network.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
EnvironmentFile=${APP_DIR}/.env
ExecStart=${JAVA_BIN} -Xms256m -Xmx512m -jar ${APP_DIR}/${JAR_NAME}
Restart=always
RestartSec=3
Environment=PORT=${PORT}

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable "$SERVICE" >/dev/null 2>&1 || true
systemctl start "$SERVICE"
info "已启动 systemd 服务 ${SERVICE}"
sleep 5
if ! systemctl is-active --quiet "$SERVICE"; then
  err "服务启动失败，最近日志："
  journalctl -u "$SERVICE" -n 20 --no-pager || true
  exit 1
fi
if ! curl -fsS "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then
  err "后端未响应，查看日志：journalctl -u ${SERVICE} -n 50"
  exit 1
fi
info "后端已就绪： http://127.0.0.1:${PORT}/"

# ---------- 7. Nginx（若未配置则写入；已配置 80→3000 则不动） ----------
if command -v nginx >/dev/null 2>&1; then
  NGINX_CONF="/etc/nginx/conf.d/sylvia.conf"
  if [ -f "$NGINX_CONF" ] && nginx -t >/dev/null 2>&1; then
    info "Nginx 配置已存在（80 → 127.0.0.1:${PORT}），无需改动"
  else
    warn "写入 Nginx 配置：$NGINX_CONF"
    cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    client_max_body_size 12m;

    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location ~ ^/s/ {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
    }
}
EOF
    nginx -t && systemctl reload nginx 2>/dev/null || service nginx reload
    info "Nginx 已配置并重载"
  fi
else
  warn "未安装 nginx，跳过（请自行配置反向代理，/api/ 需 proxy_buffering off）"
fi

# ---------- 8. 自检 ----------
info "自检 …"
check() {
  local name="$1"; local url="$2"; local expect="$3"
  local code
  code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo 000)"
  if [ "$code" = "$expect" ]; then
    info "  OK   ${name} -> ${code}"
  else
    err "  FAIL ${name} -> ${code}（期望 ${expect}）"
    return 1
  fi
}
check "首页 index.html" "http://127.0.0.1:${PORT}/" 200

# 动态提取 index.html 里实际引用的 hash 文件
IDX_HTML="$APP_DIR/public/index.html"
IDX_JS="$(grep -oP 'assets/index-[A-Za-z0-9_-]+\.js' "$IDX_HTML" 2>/dev/null | head -1 || true)"
IDX_CSS="$(grep -oP 'assets/index-[A-Za-z0-9_-]+\.css' "$IDX_HTML" 2>/dev/null | head -1 || true)"
[ -n "$IDX_JS" ]  && check "首页 JS (${IDX_JS})"   "http://127.0.0.1:${PORT}/${IDX_JS}"   200 || warn "未从 index.html 解析到 index JS"
[ -n "$IDX_CSS" ] && check "首页 CSS (${IDX_CSS})" "http://127.0.0.1:${PORT}/${IDX_CSS}"  200 || warn "未从 index.html 解析到 index CSS"

# 3 本新书封面 / 情绪图（路径按 README 约定：封面 /covers/，情绪图 /assets/）
check "新封面 fangxie"        "http://127.0.0.1:${PORT}/covers/fangxie.jpg"        200 || true
check "新封面 yumu"           "http://127.0.0.1:${PORT}/covers/yumu.jpg"           200 || true
check "新封面 xiaoqingya"     "http://127.0.0.1:${PORT}/covers/xiaoqingya.jpg"     200 || true
check "情绪图 fangxie-calm"   "http://127.0.0.1:${PORT}/assets/fangxie-calm.jpg"   200 || true
check "情绪图 yumu-crush"     "http://127.0.0.1:${PORT}/assets/yumu-crush.jpg"     200 || true
check "情绪图 xiaoqingya-dark" "http://127.0.0.1:${PORT}/assets/xiaoqingya-dark.jpg" 200 || true

API="$(curl -s --max-time 10 "http://127.0.0.1:${PORT}/api/books" 2>/dev/null || true)"
if command -v python3 >/dev/null 2>&1; then
  CNT="$(echo "$API" | python3 -c "import sys,json;d=json.load(sys.stdin);b=d.get('books',d) if isinstance(d,dict) else d;print(len(b))" 2>/dev/null || echo "$API" | grep -o '"id":' | wc -l)"
  TOP3="$(echo "$API" | python3 -c "import sys,json;d=json.load(sys.stdin);b=d.get('books',d) if isinstance(d,dict) else d;print([x.get('id') for x in b[:3]])" 2>/dev/null || echo "?")"
else
  CNT="$(echo "$API" | grep -o '"id":' | wc -l)"
  TOP3="?"
  warn "未安装 python3，TOP3 无法解析"
fi
if [ "$CNT" = "25" ]; then
  info "  OK   /api/books -> 25 本官方书"
else
  err "  FAIL /api/books 本数=${CNT}（期望 25）"
  exit 1
fi
info "  置顶前3: ${TOP3}"

# ---------- 9. 完成 ----------
echo ""
echo "==============================================="
echo "  ✅ v1.0 部署完成！"
echo "  访问： http://${DOMAIN}"
echo "  服务： systemctl status ${SERVICE}"
echo "  日志： journalctl -u ${SERVICE} -f"
echo "  备份： ${BK}"
echo "  回滚： 将 ${BK} 内 public/jar 恢复到原目录并 systemctl start 旧服务"
echo "==============================================="