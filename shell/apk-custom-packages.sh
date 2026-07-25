#!/bin/bash
set -e

# 第三方预编译包下载
# 下载到 /home/build/immortalwrt/packages/ 目录
# 同名包优先级：本地 packages/ > 官方仓库

CUSTOM_PACKAGES=""
mkdir -p /home/build/immortalwrt/packages

# ---------- 辅助函数 ----------
# 从 GitHub 下载单个文件，失败返回 1
github_download() {
  local url="$1" out="$2"
  curl -fsSL --connect-timeout 10 -o "$out" "$url" 2>/dev/null
}

# ============= sbwml mosdns（含 v2ray-geodata）=============
echo "🔄 下载 sbwml mosdns..."
MOSDNS_URL="https://github.com/sbwml/luci-app-mosdns/releases/latest/download/x86_64-openwrt-25.12.tar.gz"
if curl -fsSL --connect-timeout 10 -o /tmp/mosdns.tar.gz "$MOSDNS_URL"; then
  mkdir -p /tmp/mosdns-pkgs
  tar -zxf /tmp/mosdns.tar.gz -C /tmp/mosdns-pkgs/ 2>/dev/null || echo "⚠️ mosdns tar 解压失败"
  if [ -d /tmp/mosdns-pkgs/packages_ci ]; then
    cp /tmp/mosdns-pkgs/packages_ci/*.apk /home/build/immortalwrt/packages/
    echo "✅ mosdns 预编译包已复制"
    CUSTOM_PACKAGES="$CUSTOM_PACKAGES mosdns luci-app-mosdns luci-i18n-mosdns-zh-cn v2dat v2ray-geoip v2ray-geosite"
  else
    echo "⚠️ mosdns 压缩包中没有 packages_ci 目录"
  fi
else
  echo "⚠️ mosdns 下载失败"
fi
# ============= QiuSimons daed =============
echo "🔄 下载 QiuSimons daed..."
# API 获取最新 release 的 tag + x86_64 apk 下载地址
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
  # API 限流，用 HTTP redirect 获取最新 tag，结合硬编码文件名
  DAED_TAG=$(curl -sL -o /dev/null -w '%{url_effective}' \
    "https://github.com/QiuSimons/luci-app-daed/releases/latest" 2>/dev/null | \
    grep -o 'tag/[^/]*$' | cut -d/ -f2 || true)
  if [ -z "$DAED_TAG" ]; then
    # redirect 也失败，用完全硬编码兜底
    DAED_TAG="daed_2026.07.17-r1"
  fi
  echo "  ⚠️ API 限流，使用 redirect 获取 tag: $DAED_TAG"
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
  # 从 wukongdaily 仓库 API 获取最新 vmlinux-btf
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
    # github API 限流，硬编码最后已知版本
    BTF_NAME="vmlinux-btf-6.12.79.apk"
  fi
  BTF_URL="https://raw.githubusercontent.com/wukongdaily/apk/master/run/x86/daed/$BTF_NAME"
  if github_download "$BTF_URL" "/home/build/immortalwrt/packages/$BTF_NAME"; then
    echo "  ✅ 已下载: $BTF_NAME"
  else
    echo "  ⚠️ vmlinux-btf 下载失败"
  fi
fi

# ============= vernesong OpenClash =============
echo "🔄 下载 OpenClash..."
OC_APK_URL=$(curl -sf "https://api.github.com/repos/vernesong/OpenClash/releases/latest" 2>/dev/null | \
  python3 -c "
import sys,json
try:
    d = json.load(sys.stdin)
    for a in d.get('assets', []):
        u = a.get('browser_download_url', '')
        if u.endswith('.apk'):
            print(u)
            break
except: pass
" 2>/dev/null || true)
if [ -z "$OC_APK_URL" ]; then
  echo "  ⚠️ API 限流，跳过 OpenClash"
else
  fname=$(basename "$OC_APK_URL")
  if github_download "$OC_APK_URL" "/home/build/immortalwrt/packages/$fname"; then
    echo "  ✅ OpenClash 已下载"
    CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"
  else
    echo "  ⚠️ OpenClash 下载失败"
  fi
fi

# ============= 导出包列表 =============
echo "CUSTOM_PACKAGES=$CUSTOM_PACKAGES"
