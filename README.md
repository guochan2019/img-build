# img-build

基于 **ImmortalWrt ImageBuilder** 的 x86-64 固件快速构建项目。

无需从源码编译，下载预编译包直接组装固件，**5~10 分钟**完成一次构建。

> 🟢 **构建通过** — 2026-07-28

---

## 对比源码编译

| 特性 | 源码编译 (wrt-build) | ImageBuilder (本工程) |
|------|:------------------:|:-------------------:|
| 编译时间 | ~3h 首次 / ~40min 缓存 | **~5-10min** |
| Go 工具链 | 自编译 1.26.5 | ImageBuilder 自带 |
| 第三方包 | feeds + 源码编译 | 下载预编译 .apk |
| 复杂度 | 高（feeds/索引/冲突） | 低 |
| 定制灵活度 | 高 | 受限于预编译包 |

## 功能清单

- [x] 默认 IP **192.168.50.5**，无密码登录
- [x] 固件大小 **512MB**
- [x] frpc 中文翻译
- [x] NAS 菜单中文
- [x] **daed** + luci-app-daed（1.4 稳定版）
- [x] **mosdns** + luci-app-mosdns
- [x] **Tailscale** + luci-app-tailscale-community
- [x] **lucky / mihomo-meta / momo / nikki / quickfile**
- [x] **v2ray-geoip / v2ray-geosite**
- [x] **Nikki** v2ray 数据软链接自动创建
- [x] 主题 Argon + Kucat + Material

## 快速开始

### GitHub Actions（推荐）

1. Fork 本仓库到你的 GitHub
2. 进入 **Actions** → **Build ImmortalWrt via ImageBuilder**
3. 点击 **Run workflow**
4. 等待 5~10 分钟，在 **Release** 页面下载固件

### 本地 Docker

```bash
cd img-build

docker run --rm -i \
  --user root \
  -v "$(pwd)/bin:/home/build/immortalwrt/bin" \
  -v "$(pwd)/files:/home/build/immortalwrt/files" \
  -v "$(pwd)/x86-64/imm25.config:/home/build/immortalwrt/.config" \
  -v "$(pwd)/shell:/home/build/immortalwrt/shell" \
  -v "$(pwd)/x86-64/build.sh:/home/build/immortalwrt/build.sh" \
  immortalwrt/imagebuilder:x86-64-openwrt-25.12.1 \
  /bin/bash /home/build/immortalwrt/build.sh

# 固件输出到 bin/targets/x86/64/
```

## 项目结构

```
img-build/
├── .github/workflows/build.yml       # CI 工作流
├── x86-64/
│   ├── build.sh                       # 构建脚本
│   └── imm25.config                   # 编译配置
├── shell/
│   ├── apk-custom-packages.sh         # 预编译包下载
│   └── lmo-edit.py                    # 翻译注入工具
├── files/
│   └── etc/
│       ├── uci-defaults/99-custom.sh  # 首次启动初始化
│       └── rc.local                   # 启动脚本
└── README.md
```

## 第三方预编译包来源

| 包 | 来源 |
|---|------|
| 所有 feed 包 | [guochan2019/wrt-build](https://github.com/guochan2019/wrt-build) Release |
| vmlinux-btf（daed 依赖） | [wukongdaily/apk](https://github.com/wukongdaily/apk) |
| luci-i18n-frpc-zh-cn | ImmortalWrt 官方源 |
| base.zh-cn.lmo | ImmortalWrt 官方源 |

## CI 工作流

- **触发方式**：手动触发（`workflow_dispatch`）
- **构建容器**：`immortalwrt/imagebuilder:x86-64-openwrt-25.12.1`
- **产出**：`immortalwrt-x86-64-generic-squashfs-combined-efi.img` + `rootfs.img`

## 鸣谢

- [wukongdaily/ImmortalWrt-ImageBuilder](https://github.com/wukongdaily/ImmortalWrt-ImageBuilder) — ImageBuilder 工作流参考
- [guochan2019/wrt-build](https://github.com/guochan2019/wrt-build) — 预编译包来源
- [QiuSimons/luci-app-daed](https://github.com/QiuSimons/luci-app-daed) — daed 1.4 稳定版
