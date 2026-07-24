# img-build

基于 **ImmortalWrt ImageBuilder** 的 x86-64 固件构建项目。

不需要从源码编译，下载预编译包直接组装固件，**5~15 分钟**完成一次构建。

## 对比源码编译

| 特性 | 源码编译 (wrt-build) | ImageBuilder (本工程) |
|------|:------------------:|:-------------------:|
| 编译时间 | ~3h 首次 / ~40min 缓存 | **~5-15min** |
| Go 工具链 | 自编译 1.26.5 | 官方自带 |
| 第三方包 | feeds + 源码编译 | 下载预编译 .apk |
| 复杂度 | 高（feeds/索引/冲突） | 低 |
| 定制灵活度 | 高 | 受限于预编译包 |

## 功能清单

- [x] 默认 IP 192.168.50.5，无密码
- [x] 固件大小 256MB
- [x] **mosdns** — sbwml 版预编译包
- [x] **daed + luci-app-daed** — QiuSimons 版预编译包
- [x] **luci-app-openclash** — vernesong 版 + clash_meta 内核
- [x] **v2ray-geoip + v2ray-geosite** — sbwml 预编译包（Loyalsoldier 数据源）
- [x] **luci-app-quickfile** + nginx 配置
- [x] **Nikki** rc.local 自动软链接
- [x] **Tailscale** 追踪 GitHub 最新版本
- [x] **frpc** 中文翻译修正
- [x] 去除 qBittorrent / Aria2 / FTP / Docker CE

## 快速开始

### 方式一：GitHub Actions

1. Fork 本仓库
2. 进入 Actions → **Build ImmortalWrt via ImageBuilder**
3. 点击 **Run workflow**
4. 等待 5~15 分钟，在 Release 页面下载固件

### 方式二：本地 Docker

```bash
# 进入项目目录
cd img-build

# 运行构建
docker run --rm -i \\
  --user root \\
  -v "$(pwd)/bin:/home/build/immortalwrt/bin" \\
  -v "$(pwd)/files:/home/build/immortalwrt/files" \\
  -v "$(pwd)/x86-64/imm25.config:/home/build/immortalwrt/.config" \\
  -v "$(pwd)/shell:/home/build/immortalwrt/shell" \\
  -v "$(pwd)/x86-64/build.sh:/home/build/immortalwrt/build.sh" \\
  immortalwrt/imagebuilder:x86-64-openwrt-25.12 \\
  /bin/bash /home/build/immortalwrt/build.sh

# 固件输出到 bin/targets/x86/64/
```

## 项目结构

```
img-build/
├── .github/workflows/build.yml       # CI workflow (GitHub Actions)
├── x86-64/
│   ├── build.sh                       # 在 ImageBuilder Docker 内执行的构建脚本
│   └── imm25.config                   # 编译配置（目标/内核/驱动/镜像选项）
├── shell/
│   └── apk-custom-packages.sh         # 下载第三方预编译 .apk 包
├── files/
│   └── etc/
│       ├── uci-defaults/99-custom.sh  # 固件首次启动初始化脚本
│       └── rc.local                   # 系统启动脚本（Nikki 等）
└── README.md
```

## 第三方预编译包来源

| 包 | 来源 | 下载方式 |
|---|------|---------|
| mosdns + luci-app-mosdns | [sbwml/luci-app-mosdns](https://github.com/sbwml/luci-app-mosdns) | `.tar.gz` 解压出 `.apk` |
| v2ray-geoip / v2ray-geosite | sbwml mosdns 包内包含 | 同上 |
| daed + luci-app-daed | [QiuSimons/luci-app-daed](https://github.com/QiuSimons/luci-app-daed) | 直接下载 `.apk` |
| luci-app-openclash | [vernesong/OpenClash](https://github.com/vernesong/OpenClash) | 直接下载 `.apk` |

## 鸣谢

- [wukongdaily/ImmortalWrt-ImageBuilder](https://github.com/wukongdaily/ImmortalWrt-ImageBuilder) — ImageBuilder 工作流参考
- [sbwml/luci-app-mosdns](https://github.com/sbwml/luci-app-mosdns) — mosdns 预编译包
- [QiuSimons/luci-app-daed](https://github.com/QiuSimons/luci-app-daed) — daed 预编译包
- [vernesong/OpenClash](https://github.com/vernesong/OpenClash) — OpenClash 预编译包
