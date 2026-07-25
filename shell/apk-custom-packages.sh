#!/bin/bash
set -e

# 第三方预编译包下载
# 下载到 /home/build/immortalwrt/packages/ 目录
# 同名包优先级：本地 packages/ > 官方仓库（已设 repositories.conf）

CUSTOM_PACKAGES=""
mkdir -p /home/build/immortalwrt/packages

# ---------- 辅助函数 ----------
github_download() {
  local url="$1" out="$2"
  curl -fsSL --connect-timeout 10 -o "$out" "$url" 2>/dev/null
}

# ============= 1. feed-builder 预编译包（Nikki/Momo/lucky/quickfile/mosdns/OpenClash等）=============
echo "🔄 下载 feed-builder 预编译包..."
FB_RELEASE="https://github.com/guochan2019/feed-builder/releases/tag/Test"
# 从 Test release 获取所有 .apk 下载链接
FB_APKS=$(curl -sf "https://api.github.com/repos/guochan2019/feed-builder/releases/tags/Test" 2>/dev/null | \
  python3 -c "
import sys,json
try:
    d = json.load(sys.stdin)
    for a in d.get('assets', []):
        print(a.get('browser_download_url', ''))
except: pass
" 2>/dev/null || true)

dl_count=0
while IFS= read -r url; do
  [ -z "$url" ] && continue
  fname=$(basename "$url")
  if curl -fsSL --connect-timeout 10 -o "/home/build/immortalwrt/packages/$fname" "$url" 2>/dev/null; then
    dl_count=$((dl_count + 1))
  fi
done <<< "$FB_APKS"
echo "  ✅ feed-builder 包已下载 ($dl_count 个 .apk)"
# 所有 feed-builder 编译的包
CUSTOM_PACKAGES="$CUSTOM_PACKAGES nikki luci-app-nikki luci-i18n-nikki-zh-cn"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES mihomo-meta"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES momo luci-app-momo luci-i18n-momo-zh-cn"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES lucky luci-app-lucky luci-i18n-lucky-zh-cn"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES quickfile luci-app-quickfile luci-i18n-quickfile-zh-cn"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES mosdns luci-app-mosdns luci-i18n-mosdns-zh-cn v2dat"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES v2ray-geoip v2ray-geosite"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-frpc luci-i18n-frpc-zh-cn"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-tailscale-community luci-i18n-tailscale-community-zh-cn"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES tailscale"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-kucat"

# ============= 2. QiuSimons daed =============
echo "🔄 下载 QiuSimons daed..."
# API 获取最新 release 的 x86_64 apk 下载地址
DAED_URLS=$(curl -sf "https://api.github.com/repos/QiuSimons/luci-app-daed/releases/latest" 2>/dev/null | \
  python3 -c "
import sys,json
try:
    d = json.load(sys.stdin)
    for a in d.get('assets', []):
        u = a.get('browser_download_url', '')
        if 'x86_64-openwrt-25.12.apk' in u:
            print(u)
except: pass
" 2>/dev/null || true)

if [ -z "$DAED_URLS" ]; then
  # API 限流，硬编码 tag 和文件
  DAED_TAG="daed_2026.07.17-r1"
  DAED_URLS="https://github.com/QiuSimons/luci-app-daed/releases/download/$DAED_TAG/daed-2026.07.17-r1-x86_64-openwrt-25.12.apk
https://github.com/QiuSimons/luci-app-daed/releases/download/$DAED_TAG/luci-app-daed-1.4-r1-openwrt-25.12.apk
https://github.com/QiuSimons/luci-app-daed/releases/download/$DAED_TAG/luci-i18n-daed-zh-cn-25.283.11553.bce4b5f-openwrt-25.12.apk"
fi

all_ok=true
while IFS= read -r url; do
  [ -z "$url" ] && continue
  fname=$(basename "$url")
  target=$(echo "$fname" | sed 's/-x86_64-openwrt-25\.[0-9]\+\(\.[0-9]\+\)\?//')
  if github_download "$url" "/home/build/immortalwrt/packages/$target"; then
    echo "  ✅ $fname 已下载"
  else
    echo "  ⚠️ $fname 下载失败"
    all_ok=false
  fi
done <<< "$DAED_URLS"

if [ "$all_ok" = true ]; then
  CUSTOM_PACKAGES="$CUSTOM_PACKAGES daed luci-app-daed luci-i18n-daed-zh-cn"
  # 下载 vmlinux-btf（daed 依赖）
  echo "🔄 下载 vmlinux-btf（daed 依赖）..."
  BTF_NAME=$(curl -sf "https://api.github.com/repos/wukongdaily/apk/contents/run/x86/daed" 2>/dev/null | \
    python3 -c "
import sys,json
try:
    for item in json.load(sys.stdin):
        n = item.get('name', '')
        if 'vmlinux-btf' in n:
            print(n)
except: pass
" 2>/dev/null | sort -V | tail -1 || true)
  if [ -z "$BTF_NAME" ]; then
    BTF_NAME="vmlinux-btf-6.12.79.apk"
  fi
  BTF_URL="https://raw.githubusercontent.com/wukongdaily/apk/master/run/x86/daed/$BTF_NAME"
  if github_download "$BTF_URL" "/home/build/immortalwrt/packages/$BTF_NAME"; then
    echo "  ✅ 已下载: $BTF_NAME"
  else
    echo "  ⚠️ vmlinux-btf 下载失败"
  fi
fi

# ============= 3. 导出包列表 =============
echo "CUSTOM_PACKAGES=$CUSTOM_PACKAGES"
