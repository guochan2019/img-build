#!/bin/bash
set -e

# 第三方预编译包下载
# 下载到 /home/build/immortalwrt/packages/ 目录

CUSTOM_PACKAGES=""

# ============= sbwml mosdns =============
echo "🔄 下载 sbwml mosdns..."
MOSDNS_URL="https://github.com/sbwml/luci-app-mosdns/releases/latest/download/x86_64-openwrt-25.12.tar.gz"
if wget -qO /tmp/mosdns.tar.gz "$MOSDNS_URL"; then
  mkdir -p /tmp/mosdns-pkgs
  tar -zxf /tmp/mosdns.tar.gz -C /tmp/mosdns-pkgs/
  if [ -d /tmp/mosdns-pkgs/packages_ci ]; then
    cp /tmp/mosdns-pkgs/packages_ci/*.apk /home/build/immortalwrt/packages/ 2>/dev/null || true
    echo "✅ mosdns 包已复制"
    CUSTOM_PACKAGES="$CUSTOM_PACKAGES mosdns luci-app-mosdns luci-i18n-mosdns-zh-cn v2dat v2ray-geoip v2ray-geosite"
  fi
else
  echo "⚠️ mosdns 下载失败"
fi

# ============= QiuSimons daed =============
echo "🔄 下载 QiuSimons daed..."
DAED_TAG=$(curl -s https://api.github.com/repos/QiuSimons/luci-app-daed/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
if [ -n "$DAED_TAG" ]; then
  DAED_BASE="https://github.com/QiuSimons/luci-app-daed/releases/download/$DAED_TAG"
  for pkg in daed luci-app-daed luci-i18n-daed-zh-cn; do
    # 尝试匹配 .apk 文件（文件名格式不固定，用通配符匹配）
    PKG_URL=$(curl -s "https://api.github.com/repos/QiuSimons/luci-app-daed/releases/latest" | grep -o "https://[^\"]*${pkg}[^\"]*\.apk" | head -1)
    if [ -n "$PKG_URL" ]; then
      wget -q "$PKG_URL" -P /home/build/immortalwrt/packages/ && echo "✅ $pkg 已下载" || echo "⚠️ $pkg 下载失败"
    fi
  done
  CUSTOM_PACKAGES="$CUSTOM_PACKAGES daed luci-app-daed luci-i18n-daed-zh-cn"
else
  echo "⚠️ daed 版本获取失败"
fi

# ============= vernesong OpenClash =============
echo "🔄 下载 OpenClash..."
OC_RELEASE_URL=$(curl -s https://api.github.com/repos/vernesong/OpenClash/releases/latest | grep "browser_download_url.*\.apk" | head -1 | cut -d '"' -f 4)
if [ -n "$OC_RELEASE_URL" ]; then
  wget -q "$OC_RELEASE_URL" -P /home/build/immortalwrt/packages/ && echo "✅ OpenClash 已下载" || echo "⚠️ OpenClash 下载失败"
  CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"
fi

# ============= 导出包列表 =============
echo "CUSTOM_PACKAGES=$CUSTOM_PACKAGES"
