# SysTFTP (macOS Edition)
> 经典网络工程神器 **3CDaemon** 的现代化原生 macOS 移植版本

<p align="center">
  <img src="Assets/logo.png" width="160" height="160" alt="SysTFTP App Icon" style="border-radius: 36px; box-shadow: 0 16px 36px rgba(0,0,0,0.4);" />
</p>

<p align="center">
  <b>TFTP 服务器</b> • <b>TFTP 客户端</b> • <b>FTP 服务器</b> • <b>Syslog 日志服务器</b>
</p>

---

## 📖 项目简介 (Overview)

在网络工程、路由器/交换机刷机固件升级（如 Cisco IOS、华为 VRP、华三 Comware、锐捷 RGOS 等）、配置备份以及嵌入式设备开发中，Windows 下的 **3CDaemon** 曾经是无数网络工程师的必备利器。

然而，3CDaemon 是一款早期的 32 位 Windows 软件，长期以来官方未曾推出 macOS 版本。现代网络工程师普遍使用配备 Apple Silicon (M1/M2/M3/M4) 的 MacBook，由于 macOS 系统缺乏一体化且美观的原生网络守护工具，工程师们往往被迫使用命令行、配置 Docker 容器或开 Windows 虚拟机。

**SysTFTP** 是专为 **macOS 13+ (Ventura / Sonoma / Sequoia)** 打造的纯原生现代化重构项目：
- 采用 **Swift 5.9 / 6 + SwiftUI + Network.framework** 纯原生开发，零外部庞大依赖，启动速度飞快，内存占用极低。
- 深度融合 macOS 设计规范：深色模式 (Dark Mode)、磨砂侧边栏 (NavigationSplitView)、菜单栏小图标 (MenuBarExtra / 状态栏托盘)、原生 SF Symbols 与动画反馈。
- 完美继承并现代化增强了 3CDaemon 的所有核心功能与 Hacker 扩展选项。

---

## 🎨 Logo 设计理念 (App Icon & Logo Design)

<p align="center">
  <img src="Assets/logo.svg" width="300" height="300" alt="SysTFTP Vector Logo" />
</p>

- **形态构型**：遵循 Apple macOS 官方连续平滑超椭圆曲线（Squircle），外层具有层次分明的立体微投影与细腻的金属磨砂倒角高光。
- **色彩意象**：底色采用深邃科技蓝（Deep Space Cobalt Navy）渐变至赛博青蓝（Cyber Azure），彰显企业级网络基础设施的稳定与专业。
- **中心意象**：
  - **网络交换核心（Router Nexus Shield）**：中央正六边形核心路由器护盾，象征坚不可摧的网络服务网关。
  - **双向极速传输流（Bidirectional Stream Arrows）**：
    - 电光青蓝向上箭头代表 **TFTP / FTP 高速上传 (WRQ / STOR)**；
    - 翡翠嫩绿向下箭头代表 **TFTP / FTP 极速下载 (RRQ / RETR)**；
    - 象征双向无损、高吞吐的数据流转。
  - **Syslog 雷达监控光环（Telemetry Radar Rings）**：中心向外扩散的同心脉冲圆环，配合外围的绿、橙、青、紫事件光点，生动体现 UDP 514 实时遥测事件侦听。
  - **四守护星节点（4 Daemon Orbital Nodes）**：上下左右 4 颗精密节点，分别代表 **TFTP Server、TFTP Client、FTP Server、Syslog Server** 协同运行。
- **图标资产规格**：提供 1024×1024 矢量 SVG、无损 PNG、macOS 原生 `.icns` 以及包含 16x16 至 1024x1024 全部规格的 Xcode `AppIcon.appiconset`。

---

## ⚡ 功能特性对照 (Features vs 3CDaemon)

| 功能模块 | 经典 3CDaemon | SysTFTP (macOS 版) | 提升与增强 |
| :--- | :--- | :--- | :--- |
| **TFTP 服务器** | RFC 1350 / 1782-1784 | RFC 1350, 2347, 2348, 2349 | 支持 >16MB/32MB 16位序号安全回绕；防路径逃逸；实时传输速度计算与进度条 |
| **TFTP 客户端** | 支持 RRQ/WRQ，块协商 | 支持 RRQ/WRQ，多协议协商 | 支持 blksize (最大 65464)、timeout、tsize；历史主机下拉记录；传输暂停与取消 |
| **FTP 服务器** | RFC 765 / 959，MD5 密码 | RFC 959，PASV & PORT | 多用户隔离沙箱 (chroot)；8 项精细化权限矩阵；支持 PASV 自定义端口范围；密码加密存储并脱敏显示 |
| **Syslog 监听器**| BSD Syslog (UDP 514) | RFC 3164 / RFC 5424 | 实时高帧率流水日志；按严重级别 (Severity) 自动彩色标签；支持多条件全文检索；支持按日自动轮转 (`YYYY-MM-DD.syslog.log`) |
| **网络网卡探测** | 手动查看 IP | 自动智能探测 | 自动识别活跃物理网卡（Wi-Fi en0、Ethernet en1、USB 网卡），顶部常驻显示 IP，支持**一键复制 IP**（方便交换机命令行粘贴） |
| **系统级集成** | 仅 Windows 托盘 | macOS 状态栏菜单 (MenuBarExtra) | 驻留顶部菜单栏，可最小化后台运行，并在状态栏随时一键启停三大服务 |

---

## 📂 项目结构 (Project Structure)

```text
SysTFTP/
├── Assets/
│   ├── logo.svg                     # 矢量 Master Logo (SVG 1024x1024)
│   ├── logo.png                     # 高清 App Icon (PNG 1024x1024)
│   └── SysTFTP.icns                 # macOS 原生图标包 (.icns)
├── SysTFTP/                         # 原生 Swift/SwiftUI 源码
│   ├── App/
│   │   └── SysTFTPApp.swift         # App 声明入口与 MenuBarExtra 菜单栏集成
│   ├── Models/
│   │   ├── TFTPServerConfig.swift   # TFTP 服务端配置与传输模型
│   │   ├── TFTPClientConfig.swift   # TFTP 客户端配置与选项
│   │   ├── FTPUser.swift            # FTP 多用户模型、MD5 加密、权限矩阵与会话
│   │   ├── SyslogMessage.swift      # Syslog 消息模型、Facility/Severity 枚举与颜色
│   │   └── NetworkInterfaceInfo.swift # 本地网卡接口模型 (en0, en1, etc.)
│   ├── Services/
│   │   ├── TFTPServerService.swift  # TFTP 核心引擎 (RFC 1350, 2347, 2348, 2349)
│   │   ├── TFTPClientService.swift  # TFTP 客户端传输引擎 (并发 Socket 驱动)
│   │   ├── FTPServerService.swift   # FTP 服务端核心引擎 (PASV/PORT/权限隔离)
│   │   ├── SyslogServerService.swift# Syslog UDP 514 监听器与日志日轮转驱动
│   │   └── NetworkMonitorService.swift # Darwin getifaddrs 网卡动态监测
│   ├── ViewModels/
│   │   └── AppState.swift           # 全局协调状态机与服务代理整合
│   ├── Views/
│   │   ├── MainView.swift           # macOS 磨砂质感主分栏界面 (NavigationSplitView)
│   │   ├── OverviewView.swift       # 仪表盘总览 (4 服务卡片状态与网卡 IP 展台)
│   │   ├── TFTPServerView.swift     # TFTP 服务端管理与实时日志面板
│   │   ├── TFTPClientView.swift     # TFTP 客户端传输面板与协商选项
│   │   ├── FTPServerView.swift      # FTP 服务端用户权限管理面板
│   │   ├── SyslogServerView.swift   # Syslog 实时彩色日志流水表与导出
│   │   ├── SettingsView.swift       # 特权端口/普通端口预设与系统偏好
│   │   └── Components/
│   │       ├── StatusIndicatorView.swift # 呼吸灯运行状态组件
│   │       └── NetworkBadgeView.swift    # 顶部网卡 IP 便捷复制小胶囊
│   └── Resources/
│       ├── Info.plist               # macOS 应用程序清单配置
│       ├── SysTFTP.entitlements     # 网络与文件沙箱授权
│       └── Assets.xcassets/         # Apple 资产目录 (AppIcon & AccentColor)
├── Package.swift                    # Swift Package Manager 构建清单
├── preview.html                     # HTML5 交互式 macOS 界面仿真器 (双击即可预览!)
└── scripts/
    ├── generate_icons.py            # Python + Pillow 高清图标生成脚本
    ├── build_dmg.sh                 # macOS 下自动化编译 .app 并打包 .dmg 脚本
    └── install_port_forwarding.sh   # macOS pf 端口转发助手 (非 root 模式)
```

---

## 🛠️ 在 macOS 上编译与构建 (Building on macOS)

### 方式 1：使用 Xcode 打开
1. 在 Mac 上双击打开项目根目录的 `Package.swift`，Xcode 将自动解析项目。
2. 在顶部 Target 选择 `SysTFTP > My Mac`。
3. 点击 **Product > Run** (`Cmd + R`) 即可直接运行调试！

### 方式 2：使用命令行快速构建
```bash
# 1. 编译 Release 版本
swift build -c release

# 2. 直接运行
./.build/release/SysTFTP
```

### 方式 3：一键打包为 `.app` 与 `.dmg` 安装包
我们提供了打包脚本 `scripts/build_dmg.sh`：
```bash
chmod +x scripts/build_dmg.sh
./scripts/build_dmg.sh
```
执行后将在 `build/` 目录下生成 `SysTFTP-macOS-1.0.0.dmg`。安装窗口采用浅色背景、中文拖拽提示和固定图标布局，将左侧 SysTFTP 拖到右侧「应用程序」即可安装。背景包含普通与 Retina 两种分辨率。首次运行时，如 macOS 提示自动化权限，请允许终端控制 Finder，以便保存安装窗口布局。

### GitHub 自动发布

项目包含 `.github/workflows/release.yml`。将 Gitea 仓库的分支和版本标签镜像到 GitHub，并启用 GitHub Actions 后，推送 `v1.0.0` 形式的标签即可自动构建并发布 DMG，无需额外配置发布 Token。工作流使用 macOS Runner 构建 Apple Silicon 与 Intel 双架构应用，在无图形界面的环境中生成同样的安装窗口，并上传 DMG 和 SHA-256 校验文件到 GitHub Releases。

发布新版本时，先更新 `SysTFTP/Resources/Info.plist` 中的 `CFBundleShortVersionString`，提交代码，再创建并推送对应标签。例如：

```bash
# 将应用版本更新为 1.0.1 并提交后
git tag -a v1.0.1 -m "Release v1.0.1"
git push origin main
git push origin v1.0.1
```

分支和标签镜像到 GitHub 后会触发发布。也可以在 GitHub 的 Actions 页面手动运行 `Publish macOS DMG`，输入已存在的版本标签，补发镜像前已有的版本。重复运行会更新同版本的附件。可将中文发布说明放在 `docs/releases/<版本标签>.md`；未提供时由 GitHub 自动生成说明。

Git 仓库镜像同步代码与标签；GitHub 的 Release 和 DMG 附件由工作流独立创建。Gitea 侧也可直接上传本地打包产物。使用无图形界面的 macOS 构建机时，先安装 `scripts/dmg-requirements.txt` 中的依赖，再设置 `DMG_LAYOUT=headless` 运行打包脚本。

---

## 🔒 macOS 特权端口 (< 1024) 解决方案

如果服务监听标准端口时提示权限不足，可在应用的「设置」页直接处理：

1. **设备支持自定义端口：点击「应用普通端口」**。TFTP、FTP、Syslog 分别切换到 `6969`、`2121`、`5140`，无需管理员密码。卡片会显示「应用监听／已设为监听端口」，并展示操作结果；未启用系统转发时，连接设备也需填写这些端口。端口配置会自动保存，重新打开应用后仍会恢复。
2. **设备必须使用标准端口：点击「一键解决特权端口…」**。通过 macOS 管理员授权后，应用会监听普通端口，同时启用 IPv4 转发：UDP `69 → 6969`、TCP `21 → 2121`、UDP `514 → 5140`。页面显示「标准端口访问已启用」，并分别列出「设备访问端口」和「应用监听端口」。其他设备仍通过标准端口连接本机，SysTFTP 本身继续以普通用户权限运行。应用内还提供「检查转发状态…」和「关闭转发…」按钮；关闭后恢复显示监听端口预设。

如有服务正在运行，切换前会提示确认停止，以免显示端口与实际监听端口不一致；应用后请重新启动需要的服务。取消管理员授权不会停止服务或修改端口配置。

转发仅管理 SysTFTP 自己的 PF 规则和启用引用，不替换系统主规则，也不全局关闭 PF。系统主规则缺少所需转发入口时会提示错误，需管理员检查自定义防火墙配置。退出应用不会关闭转发，重启 macOS 后需重新启用。转发适用于其他设备发往本机的 IPv4 连接；本机测试请直接使用普通端口。

也可通过命令行管理同一套规则：

```bash
bash scripts/install_port_forwarding.sh enable
bash scripts/install_port_forwarding.sh status
bash scripts/install_port_forwarding.sh disable
```

---

## 🖥️ 快速体验界面仿真器

在当前目录直接双击打开 **`preview.html`**（或使用任何现代浏览器打开），即可全屏交互式体验 SysTFTP 在 macOS 深色模式下的真实视觉交互效果，包含服务启停模拟、网卡显示、实时日志流水与客户端传输动效！

---

## 📄 开源与致敬 (Credits & License)

- 致敬原 3Com 经典软件 **3CDaemon** 的原作者。
- 遵循 MIT License 开源，允许自由修改与定制。
