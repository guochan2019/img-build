# img-build

基于 **ImmortalWrt ImageBuilder** 的 x86-64 固件快速构建项目。

无需从源码编译，下载预编译包直接组装固件，**5~15 分钟**完成一次构建。

> 🟢 **首次构建已通过** — 2026-07-25 成功产出 `combined-efi.img`（288MB）和 `rootfs.img`（256MB）

---

## 对比源码编译

| 特性 | 源码编译 (wrt-build) | ImageBuilder (本工程) |
|------|:------------------:|:-------------------:|
| 编译时间 | ~3h 首次 / ~40min 缓存 | **~5-15min** |
| Go 工具链 | 自编译 1.26.5 | ImageBuilder 自带 |
| 第三方包 | feeds + 源码编译 | 下载预编译 .apk |
| 复杂度 | 高（feeds/索引/冲突） | 低 |
| 定制灵活度 | 高 | 受限于预编译包 |

## 功能清单

### 系统配置
- [x] 默认 IP **192.168.50.5**，无密码登录
- [x] 固件大小 **256MB**（ROOTFS_PARTSIZE）
- [x] 基础包：curl, diskman, firewall, ttyd, filemanager, openssh-sftp-server
- [x] 主题 Argon + 配置界面

### 网络增强
- [x] **mosdns** + luci-app-mosdns — sbwml 版预编译包
- [x] **daed** + luci-app-daed + 中文翻译 — QiuSimons 版预编译包
- [x] **luci-app-openclash** + clash_meta 内核 — vernesong 版
- [x] **v2ray-geoip + v2ray-geosite** — sbwml 包内含（Loyalsoldier 数据源）

### 特色定制
- [x] **Tailscale** — 追踪 GitHub 最新 release 版本，下载官方静态二进制
- [x] **frpc 中文翻译** — 下载源码编译 .lmo 覆盖官方预编译包
- [x] **Nikki rc.local** — 自动软链接 `/usr/share/v2ray/` → `/etc/nikki/run/`
- [x] **uci-defaults** — 首次启动自动初始化

### 精简
- [x] 去除 qBittorrent / Aria2 / FTP / Docker CE 等不必要包

## 快速开始

### 方式一：GitHub Actions（推荐）

1. Fork 本仓库到你的 GitHub
2. 进入 **Actions** → **Build ImmortalWrt via ImageBuilder**
3. 点击 **Run workflow**
4. （可选）填写 PPPoE 宽带账号/密码，构建后自动拨号
5. 等待 5~15 分钟，在 **Release** 页面下载固件

### 方式二：本地 Docker

```bash
cd img-build

docker run --rm -i \
  --user root \
  -v "$(pwd)/bin:/home/build/immortalwrt/bin" \
  -v "$(pwd)/files:/home/build/immortalwrt/files" \
  -v "$(pwd)/x86-64/imm25.config:/home/build/immortalwrt/.config" \
  -v "$(pwd)/shell:/home/build/immortalwrt/shell" \
  -v "$(pwd)/x86-64/build.sh:/home/build/immortalwrt/build.sh" \
  immortalwrt/imagebuilder:x86-64-openwrt-25.12 \
  /bin/bash /home/build/immortalwrt/build.sh

# 固件输出到 bin/targets/x86/64/
```

## 项目结构

```
img-build/
├── .github/workflows/build.yml       # CI 工作流（GitHub Actions）
├── x86-64/
│   ├── build.sh                       # ImageBuilder Docker 内构建脚本
│   │   ├─ 本地包仓库注册（修复 apk 相对路径 bug）
│   │   ├─ vmlinux-btf 占位包（满足 daed 依赖校验）
│   │   ├─ frpc 翻译覆盖
│   │   ├─ Tailscale 版本追踪 + 下载静态二进制
│   │   ├─ apk-custom-packages 下载第三方预编译包
│   │   ├─ OpenClash 内核下载
│   │   └─ make image 构建固件
│   └── imm25.config                   # 完整编译配置（源自 wrt-build/.config，8942 行）
├── shell/
│   └── apk-custom-packages.sh         # 下载第三方预编译 .apk 包
│       ├─ sbwml mosdns（含 v2ray-geodata）
│       ├─ QiuSimons daed
│       └─ vernesong OpenClash
├── files/
│   └── etc/
│       ├── uci-defaults/99-custom.sh  # 首次启动初始化（IP/无密码/nginx）
│       └── rc.local                   # 启动脚本（Nikki 软链接）
├── .gitignore                         # 忽略项目记忆和调研报告
├── IMG_BUILD_MEMORY.md                # 项目记忆（gitignored）
├── img-build-REPORT.md                # 调研报告（gitignored）
└── README.md
```

## 第三方预编译包来源

| 包 | 来源 | 下载方式 |
|---|------|---------|
| mosdns + luci-app-mosdns | [sbwml/luci-app-mosdns](https://github.com/sbwml/luci-app-mosdns) | `.tar.gz` → `packages_ci/*.apk` |
| v2ray-geoip / v2ray-geosite | sbwml mosdns 包内包含 | 同上 |
| daed + luci-app-daed + 中文翻译 | [QiuSimons/luci-app-daed](https://github.com/QiuSimons/luci-app-daed) | GitHub API 取最新 release → 下载 `.apk` |
| luci-app-openclash | [vernesong/OpenClash](https://github.com/vernesong/OpenClash) | GitHub API 取最新 release → 下载 `.apk` |

## CI 工作流说明

`build.yml` 工作流特性：
- **触发方式**：手动触发（`workflow_dispatch`）
- **可选输入**：luci 版本（25.12）、PPPoE 宽带账号密码
- **Runner**：`ubuntu-22.04`
- **构建容器**：`immortalwrt/imagebuilder:x86-64-openwrt-{version}`
- **产物发布**：自动上传到 Release（`ImmortalWrt-ImageBuilder` tag）
- **产出文件**：`squashfs-combined-efi.img` + `squashfs-rootfs.img`

## 鸣谢

- [wukongdaily/ImmortalWrt-ImageBuilder](https://github.com/wukongdaily/ImmortalWrt-ImageBuilder) — ImageBuilder 工作流参考
- [sbwml/luci-app-mosdns](https://github.com/sbwml/luci-app-mosdns) — mosdns 预编译包
- [QiuSimons/luci-app-daed](https://github.com/QiuSimons/luci-app-daed) — daed 预编译包
- [vernesong/OpenClash](https://github.com/vernesong/OpenClash) — OpenClash 预编译包
