#!/bin/bash
set -e

# =============================================================
# build.sh — 在 ImmortalWrt ImageBuilder Docker 内执行
# 下载第三方预编译包 → 处理翻译/版本 → 组装固件
# =============================================================

LOGFILE="/tmp/img-build-log.txt"
echo "Starting img-build at $(date)" > $LOGFILE

# ============= 1. 确保 packages/ 目录存在 =============
mkdir -p /home/build/immortalwrt/packages

# ============= 2. 第三方预编译包下载 =============
echo "🔄 下载第三方预编译包..." 
source shell/apk-custom-packages.sh

# ============= 3. 创建本地包索引（无签名 + chmod a-w 防覆盖）=============
# Makefile 内部 mkndx 输出被 >/dev/null 2>/dev/null || true 吞掉了。
# 我们手动建索引 + chmod a-w 防止被内部 mkndx 覆盖（它会先截断再签名，签名失败后索引变空）。
echo "🔄 创建本地包索引..."
APK_BIN=$(find /home/build/immortalwrt/staging_dir/host/bin -name apk -type f 2>/dev/null | head -1)
if [ -n "$APK_BIN" ]; then
  cd /home/build/immortalwrt/packages
  $APK_BIN mkndx --allow-untrusted --output packages.adb *.apk 2>&1 && \
    echo "  ✅ 索引已创建 ($(wc -c < packages.adb) bytes)" || echo "  ⚠️ mkndx 失败"
  chmod a-w packages.adb 2>/dev/null
  cd /home/build/immortalwrt
fi
echo "  packages/ 就绪: $(ls /home/build/immortalwrt/packages/*.apk 2>/dev/null | wc -l) 个 .apk"

# ============= 4. frpc 翻译处理 =============
echo "🔄 处理 frpc 翻译..."
PO2LMO=$(find /home/build/immortalwrt/staging_dir/host -name po2lmo -type f 2>/dev/null | head -1)
if [ -n "$PO2LMO" ]; then
  git clone --depth 1 https://github.com/immortalwrt/luci.git /tmp/luci-frpc 2>/dev/null || true
  if [ -f /tmp/luci-frpc/applications/luci-app-frpc/po/zh_Hans/frpc.po ]; then
    mkdir -p /home/build/immortalwrt/files/usr/lib/lua/luci/i18n
    $PO2LMO /tmp/luci-frpc/applications/luci-app-frpc/po/zh_Hans/frpc.po \
      /home/build/immortalwrt/files/usr/lib/lua/luci/i18n/frpc.zh-cn.lmo
    echo "  ✅ frpc 翻译已更新"
  fi
  rm -rf /tmp/luci-frpc
else
  echo "  ⚠️ po2lmo 不可用，frpc 翻译使用官方默认"
fi

# ============= 5. Tailscale 版本追踪 =============
echo "🔄 检查 Tailscale 最新版本..."
TS_VERSION=$(curl -s https://api.github.com/repos/tailscale/tailscale/releases/latest 2>/dev/null | \
  grep '"tag_name"' | head -1 | cut -d'"' -f4 | sed 's/^v//')
if [ -n "$TS_VERSION" ]; then
  echo "  Tailscale 最新版本: $TS_VERSION"
  wget -qO /tmp/tailscale.tar.gz \
    "https://pkgs.tailscale.com/stable/tailscale_${TS_VERSION}_amd64.tgz" 2>/dev/null || \
    wget -qO /tmp/tailscale.tar.gz \
    "https://github.com/tailscale/tailscale/releases/download/v${TS_VERSION}/tailscale_${TS_VERSION}_amd64.tgz" 2>/dev/null || true
  if [ -f /tmp/tailscale.tar.gz ]; then
    tar -zxf /tmp/tailscale.tar.gz -C /tmp/
    mkdir -p /home/build/immortalwrt/files/usr/sbin /home/build/immortalwrt/files/usr/bin
    cp /tmp/tailscale_${TS_VERSION}_amd64/tailscale /home/build/immortalwrt/files/usr/bin/tailscale 2>/dev/null
    cp /tmp/tailscale_${TS_VERSION}_amd64/tailscaled /home/build/immortalwrt/files/usr/sbin/tailscaled 2>/dev/null
    echo "  ✅ Tailscale ${TS_VERSION} 已下载"
  fi
else
  echo "  ⚠️ Tailscale 版本查询失败，使用官方仓库版本"
fi

# ============= 6. 从 .config 提取所有包 =============
# 过滤配置项别名和第三方 feed 包（不在官方仓库也不在本地 packages/ 的）
echo "🔄 从 .config 提取包列表..."
PACKAGES=""
# 需要在 .config 中排除的包（非官方仓库，不在本地 packages/）
EXCLUDE_PKGS="luci-app-lucky luci-i18n-lucky-zh-cn lucky \
  luci-app-momo luci-i18n-momo-zh-cn momo \
  luci-app-nikki luci-i18n-nikki-zh-cn nikki \
  luci-app-quickfile luci-i18n-quickfile-zh-cn quickfile \
  luci-theme-kucat mihomo-meta sing-box ariang"
while IFS='=' read -r line; do
  pkg=${line#CONFIG_PACKAGE_}
  pkg=${pkg%=y}
  # 过滤子选项
  case "$pkg" in
    dnsmasq_full_*|*_INCLUDE_*|TAR_*|knot-resolver_dnstap|luci-lib-nixio_openssl)
      continue ;;
  esac
  # 过滤不在仓库的第三方包
  skip=0
  for ep in $EXCLUDE_PKGS; do [ "$pkg" = "$ep" ] && skip=1 && break; done
  [ $skip -eq 1 ] && continue
  PACKAGES="$PACKAGES $pkg"
done < <(grep '^CONFIG_PACKAGE_.*=y' /home/build/immortalwrt/.config)

# 第三方包（已在本地 packages/ 中的）
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"
PKG_COUNT=$(echo "$PACKAGES" | wc -w)
echo "📦 共 $PKG_COUNT 个包"

# ============= 7. 配置特殊包 =============
# OpenClash 内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
  echo "🔄 下载 OpenClash 内核..."
  mkdir -p /home/build/immortalwrt/files/etc/openclash/core
  META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64-v1.tar.gz"
  wget -qO- "$META_URL" 2>/dev/null | tar xOvz > \
    /home/build/immortalwrt/files/etc/openclash/core/clash_meta 2>/dev/null || true
  if [ -f /home/build/immortalwrt/files/etc/openclash/core/clash_meta ]; then
    chmod +x /home/build/immortalwrt/files/etc/openclash/core/clash_meta
    echo "  ✅ OpenClash 内核已下载"
  fi
fi

# ============= 8. 构建镜像 =============
echo "📦 开始构建固件..."
echo "Packages: $PACKAGES"
make image PROFILE="generic" PACKAGES="$PACKAGES" \
  FILES="/home/build/immortalwrt/files" \
  ROOTFS_PARTSIZE=256

if [ $? -ne 0 ]; then
  echo "❌ 构建失败!" >> $LOGFILE
  exit 1
fi
echo "✅ 构建完成" >> $LOGFILE
