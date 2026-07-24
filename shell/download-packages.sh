#!/bin/bash
# download-packages.sh — 在 GitHub Actions 宿主机上运行
# 下载第三方预编译包到 packages/ 目录
set -e

mkdir -p packages

# ============= sbwml mosdns（含 v2ray-geodata）=============
echo "🔄 下载 sbwml mosdns..."
curl -fsSL --connect-timeout 10 \
  -o /tmp/mosdns.tar.gz \
  "https://github.com/sbwml/luci-app-mosdns/releases/latest/download/x86_64-openwrt-25.12.tar.gz"
mkdir -p /tmp/mosdns-pkgs
tar -zxf /tmp/mosdns.tar.gz -C /tmp/mosdns-pkgs/
cp /tmp/mosdns-pkgs/packages_ci/*.apk packages/
echo "✅ mosdns ($(ls packages/*.apk | wc -l) packages)"

# ============= QiuSimons daed =============
echo "🔄 下载 QiuSimons daed..."
DAED_DATA=$(curl -sf https://api.github.com/repos/QiuSimons/luci-app-daed/releases/latest)
# daed 后端（x86_64）
echo "$DAED_DATA" | grep -o "https://[^\"]*x86_64-openwrt-25\.12\.apk" | while read url; do
  curl -fsSL -o "packages/$(basename $url)" "$url" && echo "  ✅ $(basename $url)"
done
# luci-app-daed
echo "$DAED_DATA" | grep -o "https://[^\"]*luci-app-daed[^\"]*openwrt-25\.12\.apk" | while read url; do
  curl -fsSL -o "packages/$(basename $url)" "$url" && echo "  ✅ $(basename $url)"
done
# 中文翻译
echo "$DAED_DATA" | grep -o "https://[^\"]*luci-i18n-daed[^\"]*openwrt-25\.12\.apk" | while read url; do
  curl -fsSL -o "packages/$(basename $url)" "$url" && echo "  ✅ $(basename $url)"
done
echo "✅ daed done"

# ============= OpenClash =============
echo "🔄 下载 OpenClash..."
OC_DATA=$(curl -sf https://api.github.com/repos/vernesong/OpenClash/releases/latest)
OC_URL=$(echo "$OC_DATA" | grep "browser_download_url.*\.apk" | head -1 | cut -d '"' -f 4)
curl -fsSL -o "packages/$(basename $OC_URL)" "$OC_URL" && echo "✅ OpenClash"

# ============= vmlinux-btf 占位包 =============
echo "🔄 创建 vmlinux-btf 占位包..."
mkdir -p /tmp/vmlinux-btf-pkg
cat > /tmp/vmlinux-btf-pkg/.PKGINFO << 'PKGINFO'
pkgname = vmlinux-btf
pkgver = 1.0.0
pkgdesc = "Dummy package - BTF is built into kernel"
url = ""
packager = "img-build"
size = 0
architecture = all
license = "GPL-2.0-only"
PKGINFO
tar -czf packages/vmlinux-btf-1.0.0.apk -C /tmp/vmlinux-btf-pkg .

echo ""
echo "=== packages/ 内容 ==="
ls -la packages/
