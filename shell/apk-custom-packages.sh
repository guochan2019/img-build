#!/bin/bash
set -e

# 第三方预编译包下载
# 下载到 /home/build/immortalwrt/packages/ 目录
# 同名包优先级：本地 packages/ > 官方仓库

CUSTOM_PACKAGES=""
mkdir -p /home/build/immortalwrt/packages

# ---------- 辅助函数 ----------
# 从 GitHub API 获取最新 release 的下载地址
# 参数: owner/repo  返回: 下载地址列表（每行一个）
github_latest_assets() {
  local repo="$1" data urls
  data=$(curl -sf "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null || true)
  urls=$(echo "$data" | grep '"browser_download_url"' | cut -d'"' -f4)
  echo "$urls"
}

# 从 GitHub 下载单个文件，失败返回 1
github_download() {
  local url="$1" out="$2"
  curl -fsSL --connect-timeout 10 -o "$out" "$url" 2>/dev/null
}

# ============= sbwml mosdns（含 v2ray-geodata）=============
echo "🔄 下载 sbwml mosdns..."
MOSDNS_URL="https://github.com/sbwml/luci-app-mosdns/releases/latest/download/x86_64-openwrt-25.12.tar.gz"
if curl -fsSL --connect-timeout 10 -o /tmp/mosdns.tar.gz "$MOSDNS_URL"; then
  mkdir -p /tmp/mosdns-pkgs
  tar -zxf /tmp/mosdns.tar.gz -C /tmp/mosdns-pkgs/ 2>/dev/null || echo "⚠️ mosdns tar 解压失败"
  if [ -d /tmp/mosdns-pkgs/packages_ci ]; then
    cp /tmp/mosdns-pkgs/packages_ci/*.apk /home/build/immortalwrt/packages/
    echo "✅ mosdns 预编译包已复制"
    CUSTOM_PACKAGES="$CUSTOM_PACKAGES mosdns luci-app-mosdns luci-i18n-mosdns-zh-cn v2dat v2ray-geoip v2ray-geosite"
  else
    echo "⚠️ mosdns 压缩包中没有 packages_ci 目录"
  fi
else
  echo "⚠️ mosdns 下载失败"
fi
# ============= QiuSimons daed =============
echo "🔄 下载 QiuSimons daed..."
# 方案：用 HTTP redirect 获取最新 release tag（不走 API，不限流）
DAED_TAG=$(curl -sL -o /dev/null -w '%{url_effective}' \
  "https://github.com/QiuSimons/luci-app-daed/releases/latest" 2>/dev/null | \
  grep -o 'tag/[^/]*$' | cut -d/ -f2 || true)

if [ -z "$DAED_TAG" ]; then
  # 兜底：最后已知可用版本
  DAED_TAG="daed_2026.07.17-r1"
fi

DAED_BASE="https://github.com/QiuSimons/luci-app-daed/releases/download/$DAED_TAG"
# 从 release 页 HTML 提取 x86_64 的 apk 下载地址（完全不走 API）
DAED_FILES_RAW=$(curl -sL "https://github.com/QiuSimons/luci-app-daed/releases/tag/$DAED_TAG" 2>/dev/null | \
  grep -o "/download/$DAED_TAG/[^\"]*x86_64-openwrt-25\\.12\\.apk" | \
  sed "s|/download/$DAED_TAG/||" | sort -u || true)

all_ok=true
if [ -z "$DAED_FILES_RAW" ]; then
  echo "  ⚠️ 无法从 release 页提取文件名，使用 API 兜底"
  DAED_FILES_RAW=$(curl -sf "https://api.github.com/repos/QiuSimons/luci-app-daed/releases/tags/$DAED_TAG" 2>/dev/null | \
    grep -o '"name":"[^"]*x86_64-openwrt-25\\.12\\.apk"' | cut -d'"' -f4 || true)
fi
if [ -z "$DAED_FILES_RAW" ]; then
  echo "  ⚠️ 所有获取方式失败，跳过 daed 下载"
  all_ok=false
fi

while IFS= read -r fname; do
  [ -z "$fname" ] && continue
  # 重命名：去掉架构后缀使文件名匹配 {pkgname}-{pkgver}.apk 格式
  target=$(echo "$fname" | sed 's/-x86_64-openwrt-25\.[0-9]\+\(\.[0-9]\+\)\?//')
  if github_download "$DAED_BASE/$fname" "/home/build/immortalwrt/packages/$target"; then
    echo "  ✅ $fname 已下载"
  else
    echo "  ⚠️ $fname 下载失败"
    all_ok=false
  fi
done <<< "$DAED_FILES_RAW"

if [ "$all_ok" = true ]; then
  CUSTOM_PACKAGES="$CUSTOM_PACKAGES daed luci-app-daed luci-i18n-daed-zh-cn"
  # 下载 vmlinux-btf（daed 依赖），从 wukongdaily 仓库获取最新版本
  echo "🔄 下载 vmlinux-btf（daed 依赖）..."
  BTF_URL=""
  for ver in $(curl -sf "https://api.github.com/repos/wukongdaily/apk/contents/run/x86/daed" 2>/dev/null | grep -o '"name":"[^"]*vmlinux-btf[^"]*"' | cut -d'"' -f4 | sort -V); do
    BTF_URL="https://raw.githubusercontent.com/wukongdaily/apk/master/run/x86/daed/$ver"
  done
  if [ -z "$BTF_URL" ]; then
    echo "  ⚠️ wukongdaily API 获取失败，跳过 vmlinux-btf 下载"
  elif github_download "$BTF_URL" "/home/build/immortalwrt/packages/$(basename $BTF_URL)"; then
    echo "  ✅ 已下载: $(basename $BTF_URL)"
  else
    echo "  ⚠️ vmlinux-btf 下载失败"
  fi
fi

# ============= vernesong OpenClash =============
echo "🔄 下载 OpenClash..."
OC_ASSETS=$(github_latest_assets "vernesong/OpenClash")
OC_APK_URL=$(echo "$OC_ASSETS" | grep -i '\.apk$' | head -1 || true)
if [ -z "$OC_APK_URL" ]; then
  echo "  ⚠️ API 获取失败，跳过 OpenClash"
else
  fname=$(basename "$OC_APK_URL")
  if github_download "$OC_APK_URL" "/home/build/immortalwrt/packages/$fname"; then
    echo "  ✅ OpenClash 已下载"
    CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"
  else
    echo "  ⚠️ OpenClash 下载失败"
  fi
fi

# ============= 导出包列表 =============
echo "CUSTOM_PACKAGES=$CUSTOM_PACKAGES"
