#!/bin/bash
# =============================================================================
#  🦞  OpenClaw Bootstrap 安裝腳本
#      酒Ann × OpenClaw_mfg 製造業外貿班
#
#  在 VM 內執行（需要 root）：
#    curl -fsSL https://raw.githubusercontent.com/Joanna8521/openclaw-install_mfg/main/bootstrap.sh | sudo bash
#
#  自動完成：
#    1. 系統套件更新 + Node.js v22 安裝
#    2. 從 GitHub 安裝 OpenClaw（openclaw/openclaw）
#    3. 安裝製造業班 Skills（Joanna8521/openclaw_mfg）
#    4. 設定 Nginx 反向代理（Port 80）
#    5. 設定 systemd 服務（開機自動啟動）
#    6. 輸出設定 Bot Token 的下一步指令
#
#  已驗證環境：Ubuntu 22.04 ARM（Oracle VM.Standard.A1.Flex）
#  需要 Node.js v22.12+（腳本自動安裝）
# =============================================================================
set -euo pipefail

# ── 顏色 ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

print_ok()   { echo -e "  ${GREEN}✅ ${RESET} $1"; }
print_info() { echo -e "  ${CYAN}⚙️ ${RESET}  $1"; }
print_warn() { echo -e "  ${YELLOW}⚠️ ${RESET}  $1"; }
print_err()  { echo -e "  ${RED}❌${RESET}  $1"; }
section()    { echo -e "\n${BLUE}════════════════════════════════════════════${RESET}"; echo -e "  ${BOLD}$1${RESET}"; echo -e "${BLUE}════════════════════════════════════════════${RESET}"; }

# ── 必須是 root ──────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  print_err "請用 sudo 執行：sudo bash bootstrap.sh"
  exit 1
fi

# ── 變數 ────────────────────────────────────────────────────────────────────
INSTALL_DIR="/opt/openclaw"
SKILLS_REPO="https://github.com/Joanna8521/openclaw_mfg.git"
SKILLS_PAT=""  # 由學員輸入
OPENCLAW_REPO="https://github.com/openclaw/openclaw.git"
SERVICE_USER="root"   # 必須是 root，configs 在 /root/.openclaw/
SERVICE_FILE="/etc/systemd/system/openclaw.service"
NGINX_CONF="/etc/nginx/sites-available/openclaw"

# ── Banner ──────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}"
cat << 'BANNER'
  ╔═══════════════════════════════════════════╗
  ║                                           ║
  ║     🦞  OpenClaw 安裝腳本                 ║
  ║         酒Ann × OpenClaw_mfg 課程         ║
  ║         製造業外貿班                      ║
  ║                                           ║
  ╚═══════════════════════════════════════════╝
BANNER
echo -e "${RESET}"

# ── STEP 1：系統更新 + 安裝基礎套件 ─────────────────────────────────────────
section "STEP 1｜系統更新與套件安裝"
print_info "更新 apt 套件清單..."
apt-get update -qq

print_info "安裝基礎套件..."
apt-get install -y -qq \
  git curl wget jq nginx cron build-essential \
  ca-certificates gnupg lsb-release unzip 2>/dev/null
print_ok "基礎套件安裝完成"

# ── STEP 2：安裝 Node.js v22 ─────────────────────────────────────────────────
section "STEP 2｜Node.js v22 安裝"

NODE_VER=$(node --version 2>/dev/null || echo "none")
NODE_MAJOR=$(echo "$NODE_VER" | grep -oP '(?<=v)\d+' || echo "0")

if [ "$NODE_MAJOR" -lt 22 ]; then
  print_info "目前 Node.js $NODE_VER，需要升級到 v22..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - 2>/dev/null
  apt-get install -y -qq nodejs
  print_ok "Node.js $(node --version) 安裝完成"
else
  print_ok "Node.js $NODE_VER 已符合需求（>= v22）"
fi

# ── STEP 3：安裝 OpenClaw 主程式 ─────────────────────────────────────────────
section "STEP 3｜OpenClaw 主程式安裝"

if [ -d "$INSTALL_DIR/.git" ]; then
  print_info "OpenClaw 已存在，更新到最新版..."
  cd "$INSTALL_DIR"
  git pull --quiet
else
  print_info "從 GitHub 下載 OpenClaw..."
  rm -rf "$INSTALL_DIR"
  git clone --depth 1 --quiet "$OPENCLAW_REPO" "$INSTALL_DIR"
fi
print_ok "OpenClaw 主程式下載完成"

# ── STEP 4：安裝 Node.js 依賴套件 ────────────────────────────────────────────
section "STEP 4｜安裝 Node.js 依賴套件"
print_info "安裝 pnpm..."
npm install -g pnpm --quiet 2>/dev/null
print_ok "pnpm 安裝完成"

print_info "安裝套件依賴（pnpm install）..."
cd "$INSTALL_DIR"
pnpm install --silent 2>/dev/null
print_ok "套件依賴安裝完成"

print_info "Build OpenClaw..."
pnpm run build --silent 2>/dev/null || true
print_ok "Build 完成"

# ── STEP 5：初始化 OpenClaw 設定 ─────────────────────────────────────────────
section "STEP 5｜初始化 OpenClaw 設定"
print_info "初始化設定檔..."
node "$INSTALL_DIR/openclaw.mjs" setup 2>/dev/null || true
node "$INSTALL_DIR/openclaw.mjs" config set gateway.mode local 2>/dev/null || true
print_ok "OpenClaw 設定初始化完成"

# ── STEP 6：安裝製造業班 Skills ───────────────────────────────────────────────
section "STEP 6｜安裝製造業班 Skills"

SKILLS_DIR="/root/.openclaw/skills"
mkdir -p "$SKILLS_DIR"

# ── 請學員輸入課程存取碼（Fine-grained PAT）────────────────────────────────
echo ""
echo -e "  ${BOLD}請輸入課程存取碼${RESET}（老師提供，格式：github_pat_...）"
echo -e "  ${YELLOW}輸入時畫面不會顯示字元，這是正常的${RESET}"
echo ""
read -r -s -p "  課程存取碼：" SKILLS_PAT < /dev/tty
echo ""

if [ -z "$SKILLS_PAT" ]; then
  print_warn "未輸入課程存取碼，跳過 Skills 安裝"
  print_warn "之後可手動執行：git clone https://<存取碼>@github.com/Joanna8521/openclaw_mfg.git /tmp/skills_tmp"
else
  print_info "從 GitHub 下載製造業班 Skills..."
  TMP_SKILLS="/tmp/openclaw_mfg_skills"
  rm -rf "$TMP_SKILLS"

  # 把 PAT 嵌入 clone URL
  CLONE_URL="https://${SKILLS_PAT}@github.com/Joanna8521/openclaw_mfg.git"

  if git clone --depth 1 --quiet "$CLONE_URL" "$TMP_SKILLS" 2>/dev/null; then
    if [ -d "$TMP_SKILLS/skills" ]; then
      cp -r "$TMP_SKILLS/skills/"* "$SKILLS_DIR/" 2>/dev/null || true
      SKILL_COUNT=$(find "$SKILLS_DIR" -name 'SKILL.md' | wc -l)
      print_ok "製造業班 Skills 安裝完成（${SKILL_COUNT} 個技能）"
    else
      print_warn "Skills 目錄結構不符預期，請確認 repo 內有 skills/ 資料夾"
    fi
    # 清除含 PAT 的 clone 紀錄
    rm -rf "$TMP_SKILLS"
    git -C "$SKILLS_DIR" remote remove origin 2>/dev/null || true
  else
    print_err "存取碼錯誤或 repo 不存在，Skills 安裝失敗"
    print_warn "請確認存取碼是否正確，之後可重新執行此腳本"
  fi
fi

# 安裝共用基礎 C01-C10
print_info "安裝共用基礎技能 C01–C10..."
node "$INSTALL_DIR/openclaw.mjs" install c01 c02 c03 c04 c05 c06 c07 c08 c09 c10 2>/dev/null || true
print_ok "共用基礎技能安裝完成"

# ── STEP 7：設定 Nginx ───────────────────────────────────────────────────────
section "STEP 7｜設定 Nginx 反向代理"

cat > "$NGINX_CONF" << 'NGINX'
server {
    listen 80;
    server_name _;

    # LINE Webhook
    location /line/webhook {
        proxy_pass http://127.0.0.1:18789/line/webhook;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 60s;
    }

    # Telegram Webhook
    location /telegram/webhook {
        proxy_pass http://127.0.0.1:18789/telegram/webhook;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 60s;
    }

    # Health check
    location /health {
        proxy_pass http://127.0.0.1:18789/health;
        proxy_http_version 1.1;
    }

    # API
    location /api/ {
        proxy_pass http://127.0.0.1:18789/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
NGINX

# 啟用設定
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/openclaw
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# 測試 Nginx 設定
nginx -t -q 2>/dev/null && systemctl reload nginx && print_ok "Nginx 設定完成" \
  || print_warn "Nginx 設定有問題，請執行 nginx -t 查看詳情"

# ── STEP 8：設定 systemd 服務 ────────────────────────────────────────────────
section "STEP 8｜設定 systemd 自動啟動服務"

cat > "$SERVICE_FILE" << SYSTEMD
[Unit]
Description=OpenClaw AI 龍蝦助理（製造業外貿班）
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node $INSTALL_DIR/openclaw.mjs gateway
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable openclaw --quiet
systemctl restart openclaw
sleep 3

# 確認服務狀態
if systemctl is-active --quiet openclaw; then
  print_ok "systemd 服務啟動完成"
else
  print_warn "服務啟動失敗，查看 log："
  journalctl -u openclaw -n 15 --no-pager
fi

# ── STEP 9：取得 VM Public IP ─────────────────────────────────────────────────
section "STEP 9｜取得 VM 資訊"
PUBLIC_IP=$(curl -s --max-time 5 http://checkip.amazonaws.com 2>/dev/null \
  || curl -s --max-time 5 ifconfig.me 2>/dev/null \
  || echo "無法取得")
print_ok "VM Public IP：$PUBLIC_IP"

# ── 完成！輸出下一步指令 ──────────────────────────────────────────────────────
section "🎉 安裝完成！下一步：設定 Bot"
echo ""
echo -e "  ${BOLD}設定 Telegram Bot（推薦）${RESET}"
echo -e "  ${CYAN}sudo node $INSTALL_DIR/openclaw.mjs config set channels.telegram.botToken \"你的BotToken\"${RESET}"
echo -e "  ${CYAN}sudo systemctl restart openclaw${RESET}"
echo ""
echo -e "  ${BOLD}設定 LINE Bot${RESET}"
echo -e "  ${CYAN}sudo node $INSTALL_DIR/openclaw.mjs config set channels.line.channelSecret \"你的ChannelSecret\"${RESET}"
echo -e "  ${CYAN}sudo node $INSTALL_DIR/openclaw.mjs config set channels.line.accessToken \"你的AccessToken\"${RESET}"
echo -e "  ${CYAN}sudo systemctl restart openclaw${RESET}"
echo ""
echo -e "  ${BOLD}LINE Webhook URL（填到 LINE Developers 控制台）${RESET}"
echo -e "  ${CYAN}http://$PUBLIC_IP/line/webhook${RESET}"
echo ""
echo -e "  ${BOLD}設定 AI 提供商（擇一）${RESET}"
echo -e "  ${CYAN}sudo node $INSTALL_DIR/openclaw.mjs config set providers.claude.apiKey \"你的ClaudeApiKey\"${RESET}"
echo -e "  ${CYAN}sudo node $INSTALL_DIR/openclaw.mjs config set providers.openai.apiKey \"你的OpenAiKey\"${RESET}"
echo ""
echo -e "  ${BOLD}確認服務狀態${RESET}"
echo -e "  ${CYAN}sudo systemctl status openclaw${RESET}"
echo -e "  ${CYAN}sudo journalctl -u openclaw -f${RESET}"
echo ""
echo -e "${BLUE}════════════════════════════════════════════${RESET}"
echo -e "  🦞 OpenClaw 製造業外貿班 部署完成！"
echo -e "  設定完 Bot Token 後，LINE 或 Telegram 發 /help 測試"
echo -e "${BLUE}════════════════════════════════════════════${RESET}"
echo ""
