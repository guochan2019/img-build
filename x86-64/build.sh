#!/bin/bash
set -e

# =============================================================
# build.sh — 在 ImmortalWrt ImageBuilder Docker 内执行
# 下载第三方预编译包 → 处理翻译/版本 → 组装固件
# =============================================================

LOGFILE="/tmp/img-build-log.txt"
echo "Starting img-build at $(date)" > $LOGFILE

# ============= 1. 创建 vmlinux-btf 占位包（daed 依赖它）=============
# .PKGINFO 必须用 apk v3 格式（key = value），不能有逗号
mkdir -p /tmp/vmlinux-btf-pkg
cat > /tmp/vmlinux-btf-pkg/.PKGINFO << 'PKGINFO'
pkgname = vmlinux-btf
pkgver = 1.0.0
pkgdesc = Dummy package for BTF kernel support
url = 
packager = img-build
size = 0
architecture = x86_64
license = GPL-2.0-only
PKGINFO
mkdir -p /home/build/immortalwrt/packages
tar -czf /home/build/immortalwrt/packages/vmlinux-btf-1.0.0.apk -C /tmp/vmlinux-btf-pkg .
echo "  vmlinux-btf 占位包已创建"

# ============= 2. 第三方预编译包下载 =============
echo "🔄 下载第三方预编译包..." 
source shell/apk-custom-packages.sh

# ============= 3. 生成本地签名密钥 + 创建签名 packages.adb =============
# ImageBuilder 的内部 mkndx 输出被吞了（>/dev/null 2>/dev/null || true）
# 我们在 build.sh 里手动建索引并签名
echo "🔄 生成本地签名密钥..."
APK_BIN=$(find /home/build/immortalwrt/staging_dir/host/bin -name apk -type f 2>/dev/null | head -1)
mkdir -p /home/build/immortalwrt/keys
OPENSSL=$(find /home/build/immortalwrt/staging_dir/host/bin -name openssl -type f 2>/dev/null | head -1)
if [ -n "$OPENSSL" ] && [ ! -f /home/build/immortalwrt/keys/local-private-key.pem ]; then
  $OPENSSL ecparam -genkey -name prime256v1 -out /home/build/immortalwrt/keys/local-private-key.pem
  $OPENSSL ec -in /home/build/immortalwrt/keys/local-private-key.pem -pubout > /home/build/immortalwrt/keys/local-public-key.pem
  # apk 要求公钥文件首行为 untrusted comment
  sed -i '1s/^/untrusted comment: Local build key\n/' /home/build/immortalwrt/keys/local-public-key.pem 2>/dev/null || true
  echo "  ✅ 密钥已生成"
fi
if [ -n "$APK_BIN" ] && [ -f /home/build/immortalwrt/keys/local-private-key.pem ]; then
  echo "🔄 创建签名本地包索引..."
  cd /home/build/immortalwrt/packages
  $APK_BIN mkndx \
    --keys-dir /home/build/immortalwrt/keys \
    --sign /home/build/immortalwrt/keys/local-private-key.pem \
    --allow-untrusted \
    --output packages.adb \
    --rewrite-archives \
    *.apk 2>&1 && echo "  ✅ 签名索引已创建" || echo "  ⚠️ mkndx 失败"
  ls -la packages.adb 2>/dev/null
  cd /home/build/immortalwrt
fi
echo "  packages/ 就绪: $(ls /home/build/immortalwrt/packages/*.apk 2>/dev/null | wc -l) 个 .apk"

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
