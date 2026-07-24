#!/bin/bash
set -e

LOGFILE="/tmp/img-build-log.txt"
echo "Starting img-build at $(date)" > $LOGFILE

# ============= 1. frpc 翻译处理 =============
echo "🔄 处理 frpc 翻译..." >> $LOGFILE
if command -v po2lmo &>/dev/null; then
  git clone --depth 1 https://github.com/immortalwrt/luci.git /tmp/luci-frpc 2>/dev/null || true
  if [ -f /tmp/luci-frpc/applications/luci-app-frpc/po/zh_Hans/frpc.po ]; then
    mkdir -p /home/build/immortalwrt/files/usr/lib/lua/luci/i18n
    po2lmo /tmp/luci-frpc/applications/luci-app-frpc/po/zh_Hans/frpc.po \
      /home/build/immortalwrt/files/usr/lib/lua/luci/i18n/frpc.zh-cn.lmo
    echo "✅ frpc 翻译已更新" >> $LOGFILE
  fi
  rm -rf /tmp/luci-frpc
else
  echo "⚠️ po2lmo 不可用，frpc 使用官方翻译" >> $LOGFILE
fi

# ============= 2. Tailscale 版本追踪 =============
echo "🔄 检查 Tailscale 最新版本..." >> $LOGFILE
TS_VERSION=$(curl -s https://api.github.com/repos/tailscale/tailscale/releases/latest 2>/dev/null | \
  grep '"tag_name"' | head -1 | cut -d'"' -f4 | sed 's/^v//')
if [ -n "$TS_VERSION" ]; then
  echo "Tailscale 最新版本: $TS_VERSION" >> $LOGFILE
  wget -qO /tmp/tailscale.tar.gz \
    "https://pkgs.tailscale.com/stable/tailscale_${TS_VERSION}_amd64.tgz" 2>/dev/null || \
    wget -qO /tmp/tailscale.tar.gz \
    "https://github.com/tailscale/tailscale/releases/download/v${TS_VERSION}/tailscale_${TS_VERSION}_amd64.tgz" 2>/dev/null || true
  if [ -f /tmp/tailscale.tar.gz ]; then
    tar -zxf /tmp/tailscale.tar.gz -C /tmp/
    mkdir -p /home/build/immortalwrt/files/usr/sbin /home/build/immortalwrt/files/usr/bin
    cp /tmp/tailscale_${TS_VERSION}_amd64/tailscale /home/build/immortalwrt/files/usr/bin/tailscale 2>/dev/null
    cp /tmp/tailscale_${TS_VERSION}_amd64/tailscaled /home/build/immortalwrt/files/usr/sbin/tailscaled 2>/dev/null
    echo "✅ Tailscale ${TS_VERSION} 已下载" >> $LOGFILE
  fi
fi

# ============= 3. OpenClash 内核 =============
echo "🔄 下载 OpenClash 内核..." >> $LOGFILE
mkdir -p /home/build/immortalwrt/files/etc/openclash/core
META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64-v1.tar.gz"
wget -qO- "$META_URL" 2>/dev/null | tar xOvz > \
  /home/build/immortalwrt/files/etc/openclash/core/clash_meta 2>/dev/null || true
if [ -f /home/build/immortalwrt/files/etc/openclash/core/clash_meta ]; then
  chmod +x /home/build/immortalwrt/files/etc/openclash/core/clash_meta
  echo "✅ OpenClash 内核已下载" >> $LOGFILE
fi

# ============= 4. 包列表 =============
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-frpc-zh-cn"
PACKAGES="$PACKAGES tailscale"
# 第三方包（由 download-packages.sh 下载到 packages/）
PACKAGES="$PACKAGES mosdns luci-app-mosdns luci-i18n-mosdns-zh-cn v2dat v2ray-geoip v2ray-geosite"
PACKAGES="$PACKAGES daed luci-app-daed luci-i18n-daed-zh-cn"
PACKAGES="$PACKAGES luci-app-openclash"

echo "📦 Packages: $PACKAGES" >> $LOGFILE
echo "Packages: $PACKAGES"

# ============= 5. 构建镜像 =============
echo "📦 开始构建固件..." >> $LOGFILE
make image PROFILE="generic" PACKAGES="$PACKAGES" \
  FILES="/home/build/immortalwrt/files" \
  ROOTFS_PARTSIZE=256

if [ $? -ne 0 ]; then
  echo "❌ 构建失败!" >> $LOGFILE
  exit 1
fi
echo "✅ 构建完成" >> $LOGFILE
