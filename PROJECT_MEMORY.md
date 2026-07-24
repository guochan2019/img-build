# img-build 项目记忆

## 项目概述

基于 ImmortalWrt ImageBuilder 的固件构建项目，跳过源码编译，直接下载预编译包组装固件。

## 核心差异（对比 wrt-build）

| 特性 | wrt-build（源码编译） | img-build（ImageBuilder） |
|------|-------------------|------------------------|
| 编译时间 | ~3h 首次 / ~40min 缓存 | **~5-15min** |
| Go 工具链 | 源码编译 1.26.5 | ImageBuilder 自带 |
| 第三方包 | feeds + 源码编译 | 下载预编译 .apk |
| 复杂度 | 高（feeds/索引/冲突） | 低 |
| 灵活性 | 高度定制 | 受限于预编译包 |

## 第三方预编译包来源

### sbwml mosdns
- 最新 release: `https://github.com/sbwml/luci-app-mosdns/releases/latest/download/x86_64-openwrt-25.12.tar.gz`
- 包含: mosdns, luci-app-mosdns, luci-i18n-mosdns-zh-cn, v2dat, v2ray-geoip, v2ray-geosite

### QiuSimons daed
- 最新 release: `https://github.com/QiuSimons/luci-app-daed/releases/tag/daed_2026.07.17-r1`
- daed: `daed-{version}-x86_64-openwrt-25.12.apk`
- luci-app-daed: `luci-app-daed-{version}-openwrt-25.12.apk`
- luci-i18n-daed-zh-cn: `luci-i18n-daed-zh-cn-{version}-openwrt-25.12.apk`

### vernesong OpenClash
- 最新 release: `https://github.com/vernesong/OpenClash/releases/latest`
- luci-app-openclash: `luci-app-openclash-{version}.apk`

## ImageBuilder 方式

使用 immortalwrt 官方 Docker 镜像:
```
immortalwrt/imagebuilder:x86-64-openwrt-25.12
```

关键命令:
```bash
make image PROFILE="generic" PACKAGES="..." FILES="..."
```

## 工作目录结构

```
img-build/
├── .github/workflows/build.yml   # CI workflow
├── x86-64/
│   ├── build.sh                   # 在 Docker 内运行的构建脚本
│   └── imm25.config               # ImageBuilder 配置文件
├── shell/
│   ├── apk-custom-packages.sh     # 自定义包列表
│   └── apk-prepare-packages.sh    # 下载第三方预编译包
├── files/                         # 自定义固件文件（覆盖）
└── custom/                        # 用户自定义配置
```
