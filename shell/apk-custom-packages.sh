#!/bin/bash
set -e

# 第三方预编译包下载
# 下载到 /home/build/immortalwrt/packages/ 目录
# ImageBuilder 会自动优先使用本地 packages/ 中的包
# 同名包优先级：本地 packages/ > 官方仓库

CUSTOM_PACKAGES=""

# 确保 packages 目录存在
mkdir -p /home/build/immortalwrt/packages

# ============= sbwml mosdns（含 v2ray-geodata）=============
echo "🔄 下载 sbwml mosdns..."
MOSDNS_URL="https://github.com/sbwml/luci-app-mosdns/releases/latest/download/x86_64-openwrt-25.12.tar.gz"
if curl -fsSL --connect-timeout 10 -o /tmp/mosdns.tar.gz "$MOSDNS_URL"; then
  mkdir -p /tmp/mosdns-pkgs
  tar -zxf /tmp/mosdns.tar.gz -C /tmp/mosdns-pkgs/ || { echo "⚠️ mosdns tar 解压失败"; }
  if [ -d /tmp/mosdns-pkgs/packages_ci ]; then
    # 复制所有包（mosdns + luci-app-mosdns + v2ray-geoip + v2ray-geosite + v2dat）
    cp /tmp/mosdns-pkgs/packages_ci/*.apk /home/build/immortalwrt/packages/
    echo "✅ mosdns 预编译包已复制"
    echo "  📦 packages/ 内容:" >> $LOGFILE
    ls -la /home/build/immortalwrt/packages/*.apk >> $LOGFILE 2>&1
    CUSTOM_PACKAGES="$CUSTOM_PACKAGES mosdns luci-app-mosdns luci-i18n-mosdns-zh-cn v2dat v2ray-geoip v2ray-geosite"
  else
    echo "⚠️ mosdns 压缩包中没有 packages_ci 目录"
    ls -la /tmp/mosdns-pkgs/
  fi
else
  echo "⚠️ mosdns 下载失败"
fi

# ============= QiuSimons daed =============
echo "🔄 下载 QiuSimons daed..."
# 直接从 GitHub 预编译发布页下载已知文件
# URL 模式是固定的: /releases/download/{tag}/{filename}
DAED_TAG="daed_2026.07.17-r1"
DAED_BASE_URL="https://github.com/QiuSimons/luci-app-daed/releases/download/$DAED_TAG"
DAED_FILES="daed-2026.07.17-r1-x86_64-openwrt-25.12.apk luci-app-daed-1.4-r1-openwrt-25.12.apk luci-i18n-daed-zh-cn-25.283.11553.bce4b5f-openwrt-25.12.apk"
all_ok=true
for f in $DAED_FILES; do
  # 下载后重命名：去掉架构后缀使文件名匹配 mkndx 索引格式
  target_name=$(echo "$f" | sed 's/-x86_64-openwrt-25\.12//')
  curl -fsSL --connect-timeout 10 -o "/home/build/immortalwrt/packages/$target_name" "$DAED_BASE_URL/$f" && \
    echo "  ✅ $f 已下载" || { echo "  ⚠️ $f 下载失败"; all_ok=false; }
done
if [ "$all_ok" = true ]; then
  CUSTOM_PACKAGES="$CUSTOM_PACKAGES daed luci-app-daed luci-i18n-daed-zh-cn"
  # 下载 daed 依赖的 vmlinux-btf（从 wukongdaily 仓库）
  echo "🔄 下载 vmlinux-btf（daed 依赖）..."
  BTF_URL="https://raw.githubusercontent.com/wukongdaily/apk/master/run/x86/daed/vmlinux-btf-6.12.79.apk"
  curl -fsSL --connect-timeout 10 \
    -o "/home/build/immortalwrt/packages/vmlinux-btf-6.12.79.apk" \
    "$BTF_URL" && echo "  ✅ vmlinux-btf 已下载"
fi

# ============= vernesong OpenClash =============
echo "🔄 下载 OpenClash..."
OC_DATA=$(curl -sf https://api.github.com/repos/vernesong/OpenClash/releases/latest 2>/dev/null || true)
OC_APK_URL=$(echo "$OC_DATA" | grep "browser_download_url.*\\.apk" | head -1 | cut -d '"' -f 4)
if [ -n "$OC_APK_URL" ]; then
  curl -fsSL -o "/home/build/immortalwrt/packages/$(basename $OC_APK_URL)" "$OC_APK_URL" && echo "✅ OpenClash 已下载" || echo "⚠️ OpenClash 下载失败"
  CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"
else
  echo "⚠️ OpenClash 版本获取失败"
fi
# clash_meta 内核由 build.sh 处理

# ============= 导出包列表 =============
echo "CUSTOM_PACKAGES=$CUSTOM_PACKAGES"
