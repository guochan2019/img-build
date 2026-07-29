#!/bin/bash
set -eo pipefail

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

# ============= 3. packages/ 检查 =============
# .apk 已由 apk-custom-packages.sh 下载到 packages/
# 不创建自定义索引，ImageBuilder 自动处理
echo "  packages/: $(ls /home/build/immortalwrt/packages/*.apk 2>/dev/null | wc -l || true) 个 .apk"

# ============= 4. frpc 翻译处理（feed-builder 已编译 patched .lmo）=============
# frpc 的 .po 已在 feed-builder 编译前 patched: 'frp 客户端' → 'Frp 客户端'
# luci-app-frpc + luci-i18n-frpc-zh-cn 来自 feed-builder tar.gz
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

# 第三方包（已在本地 packages/ 中的）
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"
PKG_COUNT=$(echo "$PACKAGES" | wc -w)
echo "📦 共 $PKG_COUNT 个包"

# ============= 6. 构建镜像 =============
echo "📦 开始构建固件..."
ROOTFS_PARTSIZE=${ROOTFS_PARTSIZE:-512}
export ROOTFS_PARTSIZE
echo "ROOTFS_PARTSIZE: ${ROOTFS_PARTSIZE}M"
make image PROFILE="generic" PACKAGES="$PACKAGES" \
  FILES="/home/build/immortalwrt/files" \
  ROOTFS_PARTSIZE=${ROOTFS_PARTSIZE} 2>&1 | grep -vE 'WARNING:.*(UNTRUSTED|packages\.adb)'

echo "  ✅ 第一步构建完成"

# ============= 7. 用本地 .apk 强制覆写 =============
TARGET_DIR=$(find /home/build/immortalwrt/build_dir -maxdepth 3 -name 'root-*' -type d 2>/dev/null | head -1 || true)
APK_BIN="/home/build/immortalwrt/staging_dir/host/bin/apk"
echo "  📍 TARGET_DIR = $TARGET_DIR"

if [ -n "$TARGET_DIR" ] && [ -d "$TARGET_DIR" ] && [ -d "$TARGET_DIR/lib/apk/db" ]; then
  echo "  🔄 强制安装自定义包..."
  for pkg_apk in /home/build/immortalwrt/packages/daed-*.apk \
                  /home/build/immortalwrt/packages/luci-app-daed-*.apk \
                  /home/build/immortalwrt/packages/luci-i18n-daed-zh-cn-*.apk \
                  /home/build/immortalwrt/packages/tailscale-*.apk \
                  /home/build/immortalwrt/packages/v2ray-geoip-*.apk \
                  /home/build/immortalwrt/packages/v2ray-geosite-*.apk; do
    [ -f "$pkg_apk" ] || continue
    name=$(basename "$pkg_apk")
    echo "    📦 $name"
    $APK_BIN --root "$TARGET_DIR" \
      --repositories-file /dev/null \
      --allow-untrusted \
      add "$pkg_apk" 2>&1 || echo "  ⚠️ 强制安装 $name 失败"
  done
  echo "  ✅ 自定义包已强制安装"

  # daed 需要 geoip/geosite（v2ray-geoip 安装到 /usr/share/v2ray/，daed 需要 /usr/local/share/daed/）
  mkdir -p "$TARGET_DIR/usr/local/share/daed"
  if [ -f "$TARGET_DIR/usr/share/v2ray/geoip.dat" ]; then
    ln -sf "../../../share/v2ray/geoip.dat" "$TARGET_DIR/usr/local/share/daed/geoip.dat"
    echo "    ✅ geoip.dat 软链接 → /usr/local/share/daed/"
  fi
  if [ -f "$TARGET_DIR/usr/share/v2ray/geosite.dat" ]; then
    ln -sf "../../../share/v2ray/geosite.dat" "$TARGET_DIR/usr/local/share/daed/geosite.dat"
    echo "    ✅ geosite.dat 软链接 → /usr/local/share/daed/"
  fi
else
  echo "  ⚠️ 找不到 APK 数据库，跳过强制安装"
fi

# ============= 8. 重新打包（覆写后 rootfs）=============
echo "📦 重新打包..."
make build_image PROFILE="generic" 2>&1 | grep -vE 'WARNING:.*(UNTRUSTED|packages\.adb)' || true

echo "✅ 构建完成" >> $LOGFILE
