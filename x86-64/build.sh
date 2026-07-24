#!/bin/bash
set -e

# =============================================================
# build.sh — 在 ImmortalWrt ImageBuilder Docker 内执行
# 下载第三方预编译包 → 处理翻译/版本 → 组装固件
# =============================================================

LOGFILE="/tmp/img-build-log.txt"
echo "Starting img-build at $(date)" > $LOGFILE

# ============= 1. 第三方预编译包下载 =============
source shell/apk-custom-packages.sh
# 执行后 CUSTOM_PACKAGES 变量已包含所有第三方包名

# ============= vmlinux-btf 占位包 =============
# QiuSimons daed 声明依赖 vmlinux-btf，但 ImmortalWrt 25.12
# 内核已内置 BTF（/sys/kernel/btf/vmlinux），不需要独立包。
# 创建一个空 apk 占位包来满足依赖校验。
echo "🔄 创建 vmlinux-btf 占位包..." >> $LOGFILE
mkdir -p /tmp/vmlinux-btf-pkg
cat > /tmp/vmlinux-btf-pkg/.PKGINFO << 'PKGINFO'
pkgname = vmlinux-btf
pkgver = 1.0.0
pkgdesc = "Dummy package - BTF is built into 25.12 kernel"
url = ""
packager = "img-build"
size = 0
architecture = all
license = "GPL-2.0-only"
PKGINFO
tar -czf /home/build/immortalwrt/packages/vmlinux-btf-1.0.0.apk \
  -C /tmp/vmlinux-btf-pkg . 2>/dev/null && echo "✅ vmlinux-btf 占位包已创建" >> $LOGFILE

# ============= 2. frpc 翻译处理 =============
# ImageBuilder 预编译包中的翻译是 .lmo 二进制，需下载源码编译覆盖
echo "🔄 处理 frpc 翻译..." >> $LOGFILE
if command -v po2lmo &>/dev/null; then
  git clone --depth 1 https://github.com/immortalwrt/luci.git /tmp/luci-frpc 2>/dev/null || true
  if [ -f /tmp/luci-frpc/applications/luci-app-frpc/po/zh_Hans/frpc.po ]; then
    # 修改翻译：将"Frp 客户端"改为"Frp 客户端"（已一致，仅做演示）
    # 实际需要修改时取消注释以下行
    # sed -i 's/旧字符串/新字符串/g' /tmp/luci-frpc/applications/luci-app-frpc/po/zh_Hans/frpc.po
    mkdir -p /home/build/immortalwrt/files/usr/lib/lua/luci/i18n
    po2lmo /tmp/luci-frpc/applications/luci-app-frpc/po/zh_Hans/frpc.po \
      /home/build/immortalwrt/files/usr/lib/lua/luci/i18n/frpc.zh-cn.lmo
    echo "✅ frpc 翻译已更新" >> $LOGFILE
  fi
  rm -rf /tmp/luci-frpc
else
  echo "⚠️ po2lmo 不可用，frpc 翻译使用官方默认" >> $LOGFILE
fi

# ============= 3. Tailscale 版本追踪 =============
echo "🔄 检查 Tailscale 最新版本..." >> $LOGFILE
TS_VERSION=$(curl -s https://api.github.com/repos/tailscale/tailscale/releases/latest 2>/dev/null | \
  grep '"tag_name"' | head -1 | cut -d'"' -f4 | sed 's/^v//')
if [ -n "$TS_VERSION" ]; then
  echo "Tailscale 最新版本: $TS_VERSION" >> $LOGFILE
  # 下载官方静态二进制
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
else
  echo "⚠️ Tailscale 版本查询失败，使用官方仓库版本" >> $LOGFILE
fi

# ============= 4. 官方 ImmortalWrt 包列表 =============
PACKAGES=""
# 基础包
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
# FRP（有自定义翻译覆盖）
PACKAGES="$PACKAGES luci-i18n-frpc-zh-cn"
# Tailscale（用自定义二进制覆盖官方包）
PACKAGES="$PACKAGES tailscale"
# 第三方包（由 apk-custom-packages.sh 下载预编译 .apk）
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# ============= 5. 配置特殊包 =============
# OpenClash 内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
  echo "🔄 下载 OpenClash 内核..." >> $LOGFILE
  mkdir -p /home/build/immortalwrt/files/etc/openclash/core
  META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64-v1.tar.gz"
  wget -qO- "$META_URL" 2>/dev/null | tar xOvz > \
    /home/build/immortalwrt/files/etc/openclash/core/clash_meta 2>/dev/null || true
  if [ -f /home/build/immortalwrt/files/etc/openclash/core/clash_meta ]; then
    chmod +x /home/build/immortalwrt/files/etc/openclash/core/clash_meta
    echo "✅ OpenClash 内核已下载" >> $LOGFILE
  fi
fi

# ============= 6. 打印包列表 =============
echo "📦 最终包列表: $PACKAGES" >> $LOGFILE
echo "Packages: $PACKAGES"

# ============= 7. 构建镜像 =============
echo "📦 开始构建固件..." >> $LOGFILE
make image PROFILE="generic" PACKAGES="$PACKAGES" \
  FILES="/home/build/immortalwrt/files" \
  ROOTFS_PARTSIZE=256

if [ $? -ne 0 ]; then
  echo "❌ 构建失败!" >> $LOGFILE
  exit 1
fi
echo "✅ 构建完成" >> $LOGFILE
