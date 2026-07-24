# img-build

基于 **ImmortalWrt ImageBuilder** 的固件构建项目，替代传统的源码编译方式。

## 优势

| 方式 | 编译时间 | 复杂度 |
|------|---------|--------|
| 源码编译（wrt-build） | ~3h（首次）/~40min（缓存后） | 高 |
| ImageBuilder（本项目） | **~5-15min** | 低 |

## 原理

ImageBuilder 是 ImmortalWrt 官方提供的预编译包组装工具：
1. 下载官方预编译的 `.apk` 包
2. 下载第三方预编译包（sbwml mosdns、QiuSimons daed 等）
3. 组装成完整的固件镜像
4. 无源码编译，仅需打包

## 支持的第三方包

| 包 | 来源 | 预编译包 |
|---|------|:--------:|
| mosdns | sbwml/luci-app-mosdns | ✅ |
| daed | QiuSimons/luci-app-daed | ✅ |
| luci-app-openclash | vernesong/OpenClash | ✅ |
| v2ray-geodata | sbwml/v2ray-geodata | ✅ |
