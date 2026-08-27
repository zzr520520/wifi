# WiFiTool - TrollStore WiFi 安全审计工具

方案 A（MobileWiFi 私有 API 扫描）+ 方案 B（aircrack-ng 握手包字典爆破）整合架构。

## 架构概览

| 模块 | 说明 |
|------|------|
| WiFiScanner.m | 动态加载 MobileWiFi.framework 私有 API，扫描周边 AP |
| CrackManager.swift | 调用 aircrack-ng ARM64 CLI 跑握手包字典 |
| Entitlements.plist | TrollStore 巨魔权限配置（免沙盒 + WiFi 管理权限） |

## 方案 A：WiFiScanner

通过 `dlopen` 动态加载 `MobileWiFi.framework` 私有框架，调用以下私有 API：

- `WiFiManagerClientCreate` - 创建 WiFi 管理器
- `WiFiManagerClientCopyDevices` - 获取设备列表
- `WiFiDeviceClientCopyNetworks` - 扫描周边网络
- `WiFiNetworkGetProperty` - 提取 SSID/BSSID/RSSI

## 方案 B：CrackManager

在 App 内部执行交叉编译的 `aircrack-ng` ARM64 静态二进制：

- 通过 `Process` 启动子进程
- 参数：`-a 2 -b <BSSID> -w <字典路径> <cap文件>`
- 实时捕获 stdout/stderr 更新 UI

## 构建

推送至 main 分支自动触发 GitHub Actions 构建，产出 `.tipa` 文件。

需配合 Xcode 项目文件 (`WiFiTool.xcodeproj`) 和 aircrack-ng ARM64 二进制。

## 权限要求

- TrollStore 安装（免签发）
- `com.apple.private.security.no-sandbox` - 免沙盒
- `com.apple.wifi.manager-access` - WiFi 管理权限

## 声明

本项目仅供学习和安全研究参考使用。
