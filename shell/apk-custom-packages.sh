#!/bin/bash
set -e

# 第三方预编译包下载
# 下载到 /home/build/immortalwrt/packages/ 目录

CUSTOM_PACKAGES=""
mkdir -p /home/build/immortalwrt/packages

# ---------- 辅助函数 ----------
github_download() {
  local url="$1" out="$2"
  curl -fsSL --connect-timeout 10 -o "$out" "$url" 2>/dev/null
}

# ============= 1. wrt-build 预编译包（全部 8 个 feed）=============
echo "🔄 下载 wrt-build 预编译包..."
TAR_URL=$(curl -sf \
  "https://api.github.com/repos/guochan2019/wrt-build/releases/latest" 2>/dev/null | \
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
    pkg_count=$(ls /home/build/immortalwrt/packages/*.apk 2>/dev/null | wc -l) || true
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
  # ImageBuilder 25.12.x 要求 .apk 文件名与内部版本号一致
  # OpenWrt APK 内部版本用 ~ 分隔 commit hash（如 2022.12.15~47b8ee51-r4）
  # 但文件名可能用 . 替代了 ~，需修正
  newname=$(echo "$f" | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+)\.([0-9a-f]{7,})/\1~\2/')
  if [ "$f" != "$newname" ] && [ -n "$newname" ]; then
    mv "$f" "$newname" 2>/dev/null && echo "  ↪ $f → $newname"
  fi
done
cd /home/build/immortalwrt

# ============= 3. vmlinux-btf（daed 依赖）=============
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
echo "🔄 修复 frpc 翻译..."
FRPC_APK=$(ls /home/build/immortalwrt/packages/luci-i18n-frpc-zh-cn*.apk 2>/dev/null | head -1) || true
if [ -z "$FRPC_APK" ]; then
  FRPC_URL=$(curl -sfL \
    "https://downloads.immortalwrt.org/releases/25.12.1/packages/x86_64/luci/" 2>/dev/null | \
    grep -oE 'luci-i18n-frpc-zh-cn[^"]+\.apk' | head -1) || true
  if [ -n "$FRPC_URL" ]; then
    FRPC_DOWNLOAD="https://downloads.immortalwrt.org/releases/25.12.1/packages/x86_64/luci/$FRPC_URL"
    if github_download "$FRPC_DOWNLOAD" "/home/build/immortalwrt/packages/$FRPC_URL"; then
      echo "  ✅ 已下载官方 luci-i18n-frpc-zh-cn.apk"
      FRPC_APK="/home/build/immortalwrt/packages/$FRPC_URL"
    fi
  fi
fi

if [ -n "$FRPC_APK" ] && [ -f "$FRPC_APK" ]; then
  WORKDIR=$(mktemp -d)
  echo "  Extracting to $WORKDIR..."
  (cd "$WORKDIR" && /home/build/immortalwrt/staging_dir/host/bin/apk \
    --allow-untrusted extract "$FRPC_APK" 2>/dev/null) || true
  # 查找 .lmo 文件
  LMO_FILE=$(find "$WORKDIR" -name 'frpc.zh-cn.lmo' -type f 2>/dev/null | head -1) || true
  if [ -n "$LMO_FILE" ] && [ -f "$LMO_FILE" ]; then
    # 替换等长字符串："frp 客户端" → "Frp 客户端"（13字节→13字节）
    sed -i 's/frp 客户端/Frp 客户端/g' "$LMO_FILE"
    # 通过 FILES 注入（make image 时覆盖官方版）
    mkdir -p /home/build/immortalwrt/files/usr/lib/lua/luci/i18n/
    cp "$LMO_FILE" /home/build/immortalwrt/files/usr/lib/lua/luci/i18n/
    echo "  ✅ frpc 翻译已修复（FILES 注入）"
  fi
  rm -rf "$WORKDIR"
fi

# ============= 4.5 修复 NAS→存储（下载官方 base-zh-cn apk → 解包 → lmo-edit 追加）=============
echo "🔄 修复 NAS→存储..."
BASE_URL=$(curl -sfL \
  "https://downloads.immortalwrt.org/releases/25.12.1/packages/x86_64/luci/" 2>/dev/null | \
  grep -oE 'luci-i18n-base-zh-cn[^\"]+\.apk' | head -1)
curl -fsSL --connect-timeout 10 -o "/home/build/immortalwrt/packages/$BASE_URL" \
  "https://downloads.immortalwrt.org/releases/25.12.1/packages/x86_64/luci/$BASE_URL"
WORKDIR=$(mktemp -d)
(cd "$WORKDIR" && /home/build/immortalwrt/staging_dir/host/bin/apk \
  --allow-untrusted extract "/home/build/immortalwrt/packages/$BASE_URL")
LMO_FILE=$(find "$WORKDIR" -name 'base.zh-cn.lmo' -type f | head -1)
mkdir -p /home/build/immortalwrt/files/usr/lib/lua/luci/i18n/
python3 /home/build/immortalwrt/shell/lmo-edit.py \
  "$LMO_FILE" \
  /home/build/immortalwrt/files/usr/lib/lua/luci/i18n/base.zh-cn.lmo \
  "NAS" "存储"
echo "  ✅ NAS→存储 翻译已修复（lmo-edit 追加，$(stat -c%s /home/build/immortalwrt/files/usr/lib/lua/luci/i18n/base.zh-cn.lmo) bytes）"
mkdir -p "$TARGET_DIR/usr/lib/lua/luci/i18n/"
cp /home/build/immortalwrt/files/usr/lib/lua/luci/i18n/base.zh-cn.lmo \
   "$TARGET_DIR/usr/lib/lua/luci/i18n/base.zh-cn.lmo"
rm -rf "$WORKDIR"

# ============= 5. 导出包列表 =============
# PACKAGES 中已有 feed 包（来自 .config），无需重复加入 CUSTOM_PACKAGES
# CUSTOM_PACKAGES 保留旧格式输出，不改变 build.sh 引用方式
echo "CUSTOM_PACKAGES=$CUSTOM_PACKAGES"
