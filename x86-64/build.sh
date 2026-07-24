#!/bin/bash
set -e

LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting img-build at $(date)" >> $LOGFILE

# ============= 第三方预编译包 =============
echo "🔄 下载第三方预编译包..."
sh shell/apk-custom-packages.sh

# ============= 官方 ImmortalWrt 包列表 =============
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
PACKAGES="$PACKAGES luci-i18n-openclash-zh-cn"

# ============= 第三方包 =============
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# ============= mosdns 额外内核 =============
if echo "$PACKAGES" | grep -q "luci-app-mosdns"; then
  echo "✅ 已选择 luci-app-mosdns"
fi

# ============= daed 内核 =============
if echo "$PACKAGES" | grep -q "luci-app-daed"; then
  echo "✅ 已选择 luci-app-daed"
  # 下载 daed clash meta 内核
  mkdir -p files/etc/daed
fi

# ============= 构建镜像 =============
echo "📦 开始构建固件..."
echo "Packages: $PACKAGES"
make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=1024

if [ $? -ne 0 ]; then
  echo "❌ 构建失败!"
  exit 1
fi
echo "✅ 构建完成"
