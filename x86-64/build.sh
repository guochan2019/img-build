#!/bin/bash
set -e

# =============================================================
# build.sh — 在 ImmortalWrt ImageBuilder Docker 内执行
# 下载第三方预编译包 → 处理翻译/版本 → 组装固件
# =============================================================

LOGFILE="/tmp/img-build-log.txt"
echo "Starting img-build at $(date)" > $LOGFILE

# ============= 1. vmlinux-btf 占位包 =============
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

# ============= 2. 第三方预编译包下载 =============
# 必须在本地仓库注册之前，确保 packages/ 目录有所有 .apk
echo "🔄 下载第三方预编译包..." >> $LOGFILE
source shell/apk-custom-packages.sh

# ============= 3. 本地 packages/ 整理 + 重建索引 =============
# apk-custom-packages.sh 已将 .apk 下载到 packages/
# 但 ImageBuilder 的 repositories.conf 已指向 packages/，需要索引
echo "🔄 重建本地包索引..." >> $LOGFILE
cd /home/build/immortalwrt/packages
apk version 2>&1
apk index --output packages.adb --rewrite *.apk 2>&1 || echo "apk index failed (exit=$?)"
ls -la packages.adb 2>&1 || echo "packages.adb NOT created"
echo "📦 .apk count: $(ls *.apk 2>/dev/null | wc -l)"
cd /home/build/immortalwrt

# ============= 4. frpc 翻译处理 =============
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
  echo "⚠️ po2lmo 不可用，frpc 翻译使用官方默认" >> $LOGFILE
fi

# ============= 5. Tailscale 版本追踪 =============
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
else
  echo "⚠️ Tailscale 版本查询失败，使用官方仓库版本" >> $LOGFILE
fi

# ============= 6. 从 .config 提取所有包 =============
# ImageBuilder 的 make image 不读取 CONFIG_PACKAGE_*=y，
# 需要显式写入 PACKAGES= 变量。
# 同时过滤掉配置项别名（非真实包名）：
#   dnsmasq_full_* — dnsmasq-full 的子选项
#   *_INCLUDE_* — 插件的可选组件子选项
#   TAR_* — tar 压缩格式子选项
#   knot-resolver_dnstap, luci-lib-nixio_openssl — 子选项
echo "🔄 从 .config 提取包列表..." >> $LOGFILE
PACKAGES=""
while IFS='=' read -r line; do
  pkg=${line#CONFIG_PACKAGE_}
  pkg=${pkg%=y}
  # 过滤子选项：dnsmasq_full_*, *_INCLUDE_*, TAR_*, knot-resolver_dnstap, luci-lib-nixio_openssl
  case "$pkg" in
    dnsmasq_full_*|*_INCLUDE_*|TAR_*|knot-resolver_dnstap|luci-lib-nixio_openssl)
      continue ;;
  esac
  PACKAGES="$PACKAGES $pkg"
done < <(grep '^CONFIG_PACKAGE_.*=y' /home/build/immortalwrt/.config)

# 第三方包（由 apk-custom-packages.sh 下载到本地 packages/，优先级最高）
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"
PKG_COUNT=$(echo "$PACKAGES" | wc -w)
echo "📦 共 $PKG_COUNT 个包" >> $LOGFILE

# ============= 7. 配置特殊包 =============
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

# ============= 8. 打印包列表 =============
echo "📦 最终包列表: $PACKAGES" >> $LOGFILE
echo "Packages: $PACKAGES"

# ============= 9. 构建镜像 =============
echo "📦 开始构建固件..." >> $LOGFILE
make image PROFILE="generic" PACKAGES="$PACKAGES" \
  FILES="/home/build/immortalwrt/files" \
  ROOTFS_PARTSIZE=256

if [ $? -ne 0 ]; then
  echo "❌ 构建失败!" >> $LOGFILE
  exit 1
fi
echo "✅ 构建完成" >> $LOGFILE
