#!/bin/bash
set -e

# =============================================================
# build.sh — 在 ImmortalWrt ImageBuilder Docker 内执行
# 下载第三方预编译包 → 组装固件（7 步）
# =============================================================

LOGFILE="/tmp/img-build-log.txt"
echo "Starting img-build at $(date)" > $LOGFILE

# ============= 1. 确保 packages/ 目录存在 =============
mkdir -p /home/build/immortalwrt/packages

# ============= 2. 第三方预编译包下载 =============
echo "🔄 下载第三方预编译包..." 
source shell/apk-custom-packages.sh

# ============= 3. packages/ 检查 + 生成索引 =============
echo "  packages/: $(ls /home/build/immortalwrt/packages/*.apk 2>/dev/null | wc -l) 个 .apk"
cd /home/build/immortalwrt/packages
if ls *.apk >/dev/null 2>&1; then
  # 找 ImageBuilder 自带的 apk 二进制生成 .adb
  APK_BIN=$(find /home/build/immortalwrt/staging_dir -name apk -type f 2>/dev/null | head -1)
  if [ -n "$APK_BIN" ]; then
    if "$APK_BIN" mkndx --allow-untrusted --output packages.adb *.apk 2>/tmp/apk-mkndx-err.txt; then
      echo "  ✅ packages.adb 已生成"
    else
      echo "  ⚠️ packages.adb 生成失败"
    fi
  else
    echo "  ⚠️ 找不到 apk 二进制"
  fi
else
  echo "  ⚠️ 无 .apk 文件"
fi
cd /home/build/immortalwrt
# 注：ImageBuilder 的 package_install 用 --repositories-file /dev/zero，
# 所以 @local tag 不生效。APK 按版本号高低自动选包。
# 如果本地包版本 >= 官方版本，自动被选中。

# ============= 4. NAS 菜单翻译 "存储" =============
# .lmo 已预编译到 files/usr/lib/lua/luci/i18n/base.zh-cn.lmo
# 由 FILES 参数注入覆盖官方文件
echo "  ✅ NAS → 存储 翻译文件已就绪（files/ 注入）"
# frpc 翻译已由 apk-custom-packages.sh 在 .apk 内 patch
# ============= 5. 从 .config 提取所有包 =============
# 过滤配置项别名和第三方 feed 包（不在官方仓库也不在本地 packages/ 的）
echo "🔄 从 .config 提取包列表..."
PACKAGES=""
# 需要在 .config 中排除的包（feed-builder 已编译 + 官方 repo 有但无需显式加入）
EXCLUDE_PKGS="sing-box"
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

# 第三方包（已在本地 packages/ 中的）由 ImageBuilder 内置 --repository 可见
# APK 按版本号自动选最高版本，不额外添加 @local tag
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"
PKG_COUNT=$(echo "$PACKAGES" | wc -w)
echo "📦 共 $PKG_COUNT 个包"

# ============= 6. 配置特殊包 =============
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

# ============= 7. 构建镜像 =============
echo "📦 开始构建固件..."
ROOTFS_PARTSIZE=${ROOTFS_PARTSIZE:-512}
echo "Packages: $PACKAGES"
echo "ROOTFS_PARTSIZE: ${ROOTFS_PARTSIZE}M"
make image PROFILE="generic" PACKAGES="$PACKAGES" \
  FILES="/home/build/immortalwrt/files" \
  ROOTFS_PARTSIZE=${ROOTFS_PARTSIZE}

if [ $? -ne 0 ]; then
  echo "❌ 构建失败!" >> $LOGFILE
  exit 1
fi
echo "✅ 构建完成" >> $LOGFILE
