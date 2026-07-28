#!/bin/bash
set -e

# 第三方预编译包下载
# 下载到 /home/build/immortalwrt/packages/ 目录
# 同名包优先级：本地 packages/ > 官方仓库（已设 repositories.conf）

CUSTOM_PACKAGES=""
mkdir -p /home/build/immortalwrt/packages

# ---------- 辅助函数 ----------
github_download() {
  local url="$1" out="$2"
  curl -fsSL --connect-timeout 10 -o "$out" "$url" 2>/dev/null
}

# ============= 1. wrt-build 预编译包（全部 8 个 feed）=============
echo "🔄 下载 wrt-build 预编译包..."
TAR_URL=$(curl -sf "https://api.github.com/repos/guochan2019/wrt-build/releases/latest" 2>/dev/null | \
  python3 -c "
import sys,json
try:
    d = json.load(sys.stdin)
    for a in d.get('assets', []):
        if a.get('name') == 'packages-x86_64.tar.gz':
            print(a.get('browser_download_url', ''))
except: pass
" 2>/dev/null || true)

if [ -n "$TAR_URL" ]; then
  curl -fsSL --connect-timeout 15 -o /tmp/packages-x86_64.tar.gz "$TAR_URL" 2>/dev/null
  if [ -f /tmp/packages-x86_64.tar.gz ] && [ -s /tmp/packages-x86_64.tar.gz ]; then
    tar -xzf /tmp/packages-x86_64.tar.gz -C /home/build/immortalwrt/packages/
    pkg_count=$(ls /home/build/immortalwrt/packages/*.apk 2>/dev/null | wc -l)
    echo "  ✅ wrt-build 包已下载解压 ($pkg_count 个 .apk)"
  else
    echo "  ⚠️ packages-x86_64.tar.gz 下载为空或失败"
  fi
else
  echo "  ⚠️ 无法从 wrt-build Release 获取 packages-x86_64.tar.gz"
fi

# ============= 2. 文件名修复（ImageBuilder 25.12.x 校验）=============
cd /home/build/immortalwrt/packages
for f in *.apk; do
  [ ! -f "$f" ] && continue
  newname=$(echo "$f" | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+)\.([0-9a-f]{7,})/\1~\2/')
  if [ "$f" != "$newname" ] && [ -n "$newname" ]; then
    mv "$f" "$newname" 2>/dev/null && echo "  ↪ $f → $newname"
  fi
done
cd /home/build/immortalwrt

# ============= 3. vmlinux-btf（daed 依赖，非 feed 包）=============
echo "🔄 下载 vmlinux-btf..."
BTF_NAME=$(curl -sf "https://api.github.com/repos/wukongdaily/apk/contents/run/x86/daed" 2>/dev/null | \
  python3 -c "
import sys,json
try:
    for item in json.load(sys.stdin):
        n = item.get('name', '')
        if 'vmlinux-btf' in n:
            print(n)
except: pass
" 2>/dev/null | sort -V | tail -1 || true)
if [ -z "$BTF_NAME" ]; then
  BTF_NAME="vmlinux-btf-6.12.79.apk"
fi
BTF_URL="https://raw.githubusercontent.com/wukongdaily/apk/master/run/x86/daed/$BTF_NAME"
if github_download "$BTF_URL" "/home/build/immortalwrt/packages/$BTF_NAME"; then
  echo "  ✅ 已下载: $BTF_NAME"
else
  echo "  ⚠️ vmlinux-btf 下载失败"
fi

# ============= 4. frpc 翻译修复 =============
# 官方源的 luci-i18n-frpc-zh-cn 显示"frp 客户端"，
# 如果本地没有（不在第三方 8 feed 中），从官方源下载后 patch
echo "🔄 修复 frpc 翻译..."
FRPC_APK=$(ls /home/build/immortalwrt/packages/luci-i18n-frpc-zh-cn*.apk 2>/dev/null | head -1)
if [ -z "$FRPC_APK" ]; then
  # 从 ImmortalWrt 25.12.1 官方源下载
  FRPC_URL=$(curl -sfL "https://downloads.immortalwrt.org/releases/25.12.1/packages/x86_64/luci/" 2>/dev/null | \
    grep -o 'luci-i18n-frpc-zh-cn[^"]*\.apk' | head -1)
  if [ -n "$FRPC_URL" ]; then
    FRPC_APK="/home/build/immortalwrt/packages/$FRPC_URL"
    curl -fsSL --connect-timeout 10 -o "$FRPC_APK" \
      "https://downloads.immortalwrt.org/releases/25.12.1/packages/x86_64/luci/$FRPC_URL" 2>/dev/null && \
      echo "  ✅ 已下载官方 luci-i18n-frpc-zh-cn.apk" || \
      echo "  ⚠️ 官方 frpc 下载失败"
  fi
  # 再次检查
  FRPC_APK=$(ls /home/build/immortalwrt/packages/luci-i18n-frpc-zh-cn*.apk 2>/dev/null | head -1)
fi
if [ -n "$FRPC_APK" ]; then
  # APK 是 tar.gz 格式，解包 → patch .lmo → 重新打包
  WORKDIR=$(mktemp -d)
  tar -xzf "$FRPC_APK" -C "$WORKDIR" 2>/dev/null
  LMO_FILE=$(find "$WORKDIR" -name 'frpc.zh-cn.lmo' -type f 2>/dev/null | head -1)
  if [ -n "$LMO_FILE" ]; then
    # "frp 客户端" 和 "Frp 客户端" UTF-8 字节数相同（13 字节），直接 sed 替换安全
    sed -i 's/frp 客户端/Frp 客户端/g' "$LMO_FILE"
    # 重新打包为 APK（保留 .PKGINFO .apk-receipt 等元数据）
    rm -f "$FRPC_APK"
    cd "$WORKDIR"
    tar -czf "$FRPC_APK" . 2>/dev/null
    cd /home/build/immortalwrt
    echo "  ✅ frpc 翻译已修复: frp 客户端 → Frp 客户端"
  else
    echo "  ⚠️ 未找到 frpc.zh-cn.lmo"
  fi
  rm -rf "$WORKDIR"
else
  echo "  ⚠️ 未找到 luci-i18n-frpc-zh-cn.apk，跳过"
fi

# ============= 5. 包列表 =============
# wrt-build 已编译 8 个 feed 的全部包：
#   daed: daed luci-app-daed luci-i18n-daed-zh-cn
#   lucky: lucky luci-app-lucky luci-i18n-lucky-zh-cn
#   Nikki: nikki luci-app-nikki luci-i18n-nikki-zh-cn mihomo-meta
#   Momo: momo luci-app-momo luci-i18n-momo-zh-cn
#   mosdns: mosdns luci-app-mosdns luci-i18n-mosdns-zh-cn v2dat
#   quickfile: quickfile luci-app-quickfile luci-i18n-quickfile-zh-cn
#   OpenClash: luci-app-openclash
#   myownpack: luci-theme-kucat
CUSTOM_PACKAGES="$CUSTOM_PACKAGES daed luci-app-daed luci-i18n-daed-zh-cn"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES lucky luci-app-lucky luci-i18n-lucky-zh-cn"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES nikki luci-app-nikki luci-i18n-nikki-zh-cn mihomo-meta"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES momo luci-app-momo luci-i18n-momo-zh-cn"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES mosdns luci-app-mosdns luci-i18n-mosdns-zh-cn v2dat"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES quickfile luci-app-quickfile luci-i18n-quickfile-zh-cn"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-kucat"

echo "CUSTOM_PACKAGES=$CUSTOM_PACKAGES"
