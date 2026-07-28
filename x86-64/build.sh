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
# 手动生成 .adb，确保 APK 读到 repositories 时文件已存在
cd /home/build/immortalwrt/packages
if ls *.apk >/dev/null 2>&1; then
  apk mkndx --allow-untrusted --output packages.adb *.apk 2>/dev/null && \
    echo "  ✅ packages.adb 已生成" || \
    echo "  ⚠️ packages.adb 生成失败"
  cd /home/build/immortalwrt
  # 确认 .adb 存在后再插入 repositories
  if [ -f packages/packages.adb ]; then
    sed -i '1i @local /home/build/immortalwrt/packages/packages.adb' \
      /home/build/immortalwrt/repositories 2>/dev/null || true
    echo "  ✅ @local 仓库已注册"
  fi
else
  cd /home/build/immortalwrt
  echo "  ⚠️ 无 .apk 文件，跳过本地仓库注册"
fi

# ============= 4. NAS 菜单翻译 "存储" =============
# 一级菜单 "NAS" 在中文界面显示为 "存储"
# 用 po2lmo 编译一个 patched .lmo，通过 FILES 注入覆盖
echo "🔄 编译 NAS → 存储 翻译..."
PO2LMO=$(find /home/build/immortalwrt/staging_dir -name po2lmo -type f 2>/dev/null | head -1)
if [ -n "$PO2LMO" ]; then
  mkdir -p files/usr/lib/lua/luci/i18n
  cat > /tmp/nas.po << 'POEOF'
msgid ""
msgstr ""
"Language: zh_Hans\n"
"Content-Type: text/plain; charset=UTF-8\n"

msgid "NAS"
msgstr "存储"
POEOF
  "$PO2LMO" /tmp/nas.po /home/build/immortalwrt/files/usr/lib/lua/luci/i18n/base.zh-cn.lmo 2>/dev/null && \
    echo "  ✅ NAS → 存储 翻译已注入" || \
    echo "  ⚠️ po2lmo 编译失败"
else
  echo "  ⚠️ 找不到 po2lmo，跳过"
fi
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

# 第三方包（已在本地 packages/ 中的）
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"
PKG_COUNT=$(echo "$PACKAGES" | wc -w)
echo "📦 共 $PKG_COUNT 个包"

# 对 daed/openclash 加 @local tag，强制只从本地源安装
# (^| )/( |$) 锚定防误匹配 hyphen 子串
PACKAGES=$(echo "$PACKAGES" | sed -E \
  -e 's/(^| )daed( |$)/\1daed@local\2/g' \
  -e 's/(^| )luci-app-daed( |$)/\1luci-app-daed@local\2/g' \
  -e 's/(^| )luci-i18n-daed-zh-cn( |$)/\1luci-i18n-daed-zh-cn@local\2/g' \
  -e 's/(^| )luci-app-openclash( |$)/\1luci-app-openclash@local\2/g')

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
