#!/bin/bash
set -e

# 第三方预编译包下载
# 下载到 /home/build/immortalwrt/packages/ 目录
# ImageBuilder 会自动优先使用本地 packages/ 中的包
# 同名包优先级：本地 packages/ > 官方仓库

CUSTOM_PACKAGES=""

# ============= sbwml mosdns（含 v2ray-geodata）=============
echo "🔄 下载 sbwml mosdns..."
MOSDNS_URL="https://github.com/sbwml/luci-app-mosdns/releases/latest/download/x86_64-openwrt-25.12.tar.gz"
if wget -qO /tmp/mosdns.tar.gz "$MOSDNS_URL"; then
  mkdir -p /tmp/mosdns-pkgs
  tar -zxf /tmp/mosdns.tar.gz -C /tmp/mosdns-pkgs/
  if [ -d /tmp/mosdns-pkgs/packages_ci ]; then
    # 复制所有包（mosdns + luci-app-mosdns + v2ray-geoip + v2ray-geosite + v2dat）
    cp /tmp/mosdns-pkgs/packages_ci/*.apk /home/build/immortalwrt/packages/ 2>/dev/null || true
    echo "✅ mosdns 预编译包已复制"
    CUSTOM_PACKAGES="$CUSTOM_PACKAGES mosdns luci-app-mosdns luci-i18n-mosdns-zh-cn v2dat v2ray-geoip v2ray-geosite"
  fi
else
  echo "⚠️ mosdns 下载失败，将使用官方仓库版"
fi

# ============= QiuSimons daed =============
echo "🔄 下载 QiuSimons daed..."
DAED_DATA=$(curl -sf https://api.github.com/repos/QiuSimons/luci-app-daed/releases/latest)
DAED_TAG=$(echo "$DAED_DATA" | grep '"tag_name"' | cut -d'"' -f4)
if [ -n "$DAED_TAG" ]; then
  # 下载 daed 后端（x86_64 + openwrt-25.12）
  echo "$DAED_DATA" | grep -o "https://[^\"]*x86_64-openwrt-25\.12\.apk" | while read url; do
    wget -q "$url" -P /home/build/immortalwrt/packages/ && echo "  ✅ $(basename $url) 已下载" || echo "  ⚠️ $(basename $url) 下载失败"
  done
  # 下载 luci-app-daed（不区分架构）
  echo "$DAED_DATA" | grep -o "https://[^\"]*luci-app-daed[^\"]*openwrt-25\.12\.apk" | while read url; do
    wget -q "$url" -P /home/build/immortalwrt/packages/ && echo "  ✅ $(basename $url) 已下载" || echo "  ⚠️ $(basename $url) 下载失败"
  done
  # 下载中文翻译
  echo "$DAED_DATA" | grep -o "https://[^\"]*luci-i18n-daed[^\"]*openwrt-25\.12\.apk" | while read url; do
    wget -q "$url" -P /home/build/immortalwrt/packages/ && echo "  ✅ $(basename $url) 已下载" || echo "  ⚠️ $(basename $url) 下载失败"
  done
  CUSTOM_PACKAGES="$CUSTOM_PACKAGES daed luci-app-daed luci-i18n-daed-zh-cn"
else
  echo "⚠️ daed 版本获取失败，将使用官方仓库版"
fi

# ============= vernesong OpenClash =============
echo "🔄 下载 OpenClash..."
OC_DATA=$(curl -sf https://api.github.com/repos/vernesong/OpenClash/releases/latest)
OC_APK_URL=$(echo "$OC_DATA" | grep "browser_download_url.*\.apk" | head -1 | cut -d '"' -f 4)
if [ -n "$OC_APK_URL" ]; then
  wget -q "$OC_APK_URL" -P /home/build/immortalwrt/packages/ && echo "✅ OpenClash 已下载" || echo "⚠️ OpenClash 下载失败"
  CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"
fi
# clash_meta 内核由 build.sh 处理

# ============= 导出包列表 =============
echo "CUSTOM_PACKAGES=$CUSTOM_PACKAGES"
