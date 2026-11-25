# SnipX

**随手截，随处贴。**

SnipX 是一款专为 macOS 打造的轻量级原生菜单栏截图工具。基于 Swift、`AppKit` 与 `ScreenCaptureKit` 纯原生构建，零第三方依赖，集**区域截图、窗口截图、全屏截图、滚动长截图、丰富标注编辑与桌面置顶贴图**于一体。所有图像处理均在本机内存中完成，不联网、不上传。

---

## 功能特性

### 1. 四种截图模式
- **区域截图**：自由拖拽框选，松开鼠标后支持二次精调——拖动选区内部平移、拖动 8 个边框/四角控制柄缩放、使用方向键像素级微调，支持多显示器与 Retina 高清像素级裁剪。
- **窗口截图**：鼠标悬停自动识别并高亮屏幕上的独立窗口（自动过滤桌面元素与自身进程），基于 `ScreenCaptureKit` 无阴影高清捕获。
- **全屏截图**：一键点击截取鼠标所在显示器的完整高分屏画面。
- **滚动长截图**：框选可滚动内容区域后缓慢向下滚动，内置灰度降采样特征匹配与防抖判稳算法，自动剔除静止重复帧与歧义重复纹理，无缝拼接长页面（最高支持 `30,000 px` 高度或 `8,000 万` 总像素）。

### 2. 内置标注编辑器
- **8 种标注工具**：矩形、椭圆、直线、箭头、画笔、马赛克（实时像素化遮罩）、文字、自动递增步骤编号（`① ② ③…`）。
- **样式与视图控制**：自由选色器、三档线宽/字号切换（细 / 中 / 粗）、`3%–400%` 缩放与「适合窗口」自适应、右键拖拽画布平移。
- **非破坏性交互编辑**：
  - 鼠标悬停已有标注自动切换抓手光标，**左键直接拖拽即可移动已有标注**；
  - 按住 `⌥ Option` 键点击/拖拽，可在已有标注上方强制绘制新标注；
  - 完整支持多步撤销（`⌘Z`）与重做（`⇧⌘Z`）。
- **多路输出**：一键复制 PNG 到剪贴板、保存为 PNG / JPEG 文件（默认带时间戳命名）、一键转为桌面置顶贴图，或继续发起滚动长截图。支持同时打开多个编辑器窗口。

### 3. 桌面置顶贴图（Pin）
- 将截图或标注结果钉在屏幕最顶层，跨桌面空间（Spaces）与全屏应用常驻显示，适合对照参考代码、设计稿或账单数据。
- 支持任意位置拖拽移动、锁定原始宽高比自由缩放（最小 `80 × 80`）。
- 右键菜单支持快速复制图像、保存文件、切换**半透明（55%）/ 不透明（100%）**或关闭贴图；菜单栏支持一键「关闭所有贴图」。

### 4. 原生系统集成
- **菜单栏常驻**：无 Dock 图标打扰（`LSUIElement`）。
- **全局快捷键**：默认 `⇧⌘2` 呼出截图，可在设置面板中录制自定义快捷键（需包含 `⌘`、`⌃` 或 `⌥` 修饰键）。
- **登录时自动启动**：基于 `ServiceManagement`（`SMAppService`）与系统登录项实时同步状态。

---

## 系统要求

- **操作系统**：macOS 14.0 (Sonoma) 或更高版本（macOS 15.0+ 支持系统原生八向边框缩放光标）
- **处理器架构**：Apple Silicon (`arm64`)（源码亦可通过 SwiftPM 在当前主机架构下编译）
- **构建环境**（从源码编译时）：Xcode 16+ / Swift 6.0+ 工具链
- **系统权限**：首次截图需在「系统设置 → 隐私与安全性 → 屏幕与系统音频录制」中授予 SnipX 权限

---

## 快速开始

### 直接下载 DMG 安装（推荐）

前往 [**GitHub Releases**](https://github.com/gekowa/SnipX/releases/latest) 下载最新版本的 `SnipX-<version>.dmg`：

1. 双击打开 `.dmg` 镜像，将 **`SnipX.app`** 拖入 **`Applications`（应用程序）** 目录。
2. 由于应用默认采用无证书 Ad-hoc 签名（未经过 Apple 公证），首次启动若遇到系统拦截提示，请在终端执行以下命令清除下载隔离属性后再打开：
   ```bash
   xattr -cr /Applications/SnipX.app
   ```
3. 打开应用后，按提示在「系统设置 → 隐私与安全性 → 屏幕与系统音频录制」中开启 SnipX 权限。

### 从源码打包并运行应用

项目提供一键打包脚本，编译 Release 产物并封装为已签名的 `dist/SnipX.app` 或 `dist/SnipX-<version>.dmg`：

```bash
# 构建 dist/SnipX.app
./scripts/build.sh
open dist/SnipX.app

# 构建可分发安装包 dist/SnipX-1.0.0.dmg（附带 SHA-256 校验文件）
./scripts/build-dmg.sh
```

> **提示**：
> - 如需使用「登录时自动启动」功能，建议将构建好的 `dist/SnipX.app` 拖入 `/Applications`（应用程序）目录后运行。
> - 默认使用本地 Ad-hoc 签名（`-`）。若拥有开发者证书，可通过环境变量指定签名身份：
>   ```bash
>   SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build.sh
>   ```
> - 重新进行 Ad-hoc 签名打包后，若 macOS 屏幕录制权限缓存失效，可执行以下命令重置授权后重新勾选：
>   ```bash
>   tccutil reset ScreenCapture com.snipx.app
>   ```

### 开发构建与单元测试

```bash
# 编译 Debug 版本
swift build --scratch-path .build

# 运行全部单元测试（SnipCoreTests + SnipXTests）
swift test --scratch-path .build

# 运行启动冒烟测试（写入系统信息至 /private/tmp/snipx-smoke.txt 后自动退出）
dist/SnipX.app/Contents/MacOS/SnipX --smoke-test
```

---

## 快捷键与操作速查

### 全局与选区遮罩
| 快捷键 / 操作 | 功能说明 |
| :--- | :--- |
| `⇧⌘2`（默认，可自定义） | 随时启动区域截图 |
| `1` / `2` / `3` / `4` | 在选区遮罩中切换：**区域 / 窗口 / 全屏 / 长截图** |
| `Space`（空格） | 在选区遮罩中快速切换至**窗口截图**模式 |
| 拖拽选区内部 / 8 个控制柄 | 移动选区位置 / 调整选区边缘与四角大小 |
| 选区外部重新拖拽 | 放弃当前选区并重新框选 |
| `↑` `↓` `←` `→` | 按 `1 pt` 微调选区位置（按住 `⇧ Shift` 按 `10 pt` 加速移动） |
| `Enter` / `Return` | 确认选区并打开编辑器（长截图模式下进入滚动捕获） |
| `Esc` | 取消当前截图或取消快捷键录制 |

### 标注编辑器
| 快捷键 / 操作 | 功能说明 |
| :--- | :--- |
| 左键拖拽空白处 | 使用当前选中工具绘制标注 |
| 左键拖拽已有标注 | 移动该标注位置 |
| `⌥ Option` + 左键拖拽 | 忽略下方已有标注，强制在重叠位置绘制新标注 |
| 右键拖拽画布 | 平移滚动放大后的截图画布 |
| `⌘Z` / `⇧⌘Z` | 撤销 / 重做上一步标注或移动操作（工具栏撤销按钮右键亦可触发重做） |

### 滚动长截图技巧
1. 进入「滚动长截图」模式后，**仅框选内部可滚动的内容区域**，避开网页/应用顶部吸顶导航栏、底部固定状态栏或侧边悬浮按钮，按 `Enter` 确认。
2. 缓慢向下滚动鼠标滚轮或触控板，**每次滚动后短暂悬停片刻**（约 `0.4s`），待悬浮面板提示帧数增加后继续向下滚动。
3. 滚动到底部后点击悬浮面板上的 **「完成」** 即可将完整长图送入标注编辑器。

---

## 项目架构

项目采用 Swift Package Manager 组织，将纯核心算法库与 macOS 系统 UI 层解耦：

```text
SnipX/
├── .github/workflows/
│   └── release.yml                # GitHub Actions 自动测试、打包 DMG 并发布至 Release
├── Package.swift                  # SwiftPM 配置（SnipCore 库 + SnipX 可执行程序 + 测试目标）
├── Resources/
│   └── Info.plist                 # 应用 Bundle 元信息、LSUIElement 与屏幕录制权限描述
├── scripts/
│   ├── build.sh                   # Release 编译、.app 目录组装与 codesign 签名脚本
│   └── build-dmg.sh               # 生成带 Applications 快捷方式的 UDZO .dmg 镜像与 SHA-256 校验文件
├── Sources/
│   ├── SnipCore/                  # 纯算法与几何核心层（仅依赖 Foundation + CoreGraphics）
│   │   ├── Geometry.swift         # 框选矩形归一化、AppKit/Quartz 坐标系换算、Retina 像素裁剪换算
│   │   ├── AdjustableSelection.swift # 可调整选区状态机（创建、移动、8 控制柄缩放、键盘微调与边界钳制）
│   │   └── ScrollMatcher.swift    # 灰度降采样帧（GrayFrame）、滚动偏移匹配（ScrollMatcher）与长图拼接（ImageStitcher）
│   └── SnipX/                     # macOS 应用交互层（AppKit + ScreenCaptureKit + Carbon + CoreImage）
│       ├── App.swift              # 应用入口、菜单栏状态项、设置与说明窗口、SMAppService 开机自启管理
│       ├── CaptureService.swift   # ScreenCaptureKit 权限预检、多屏快照与独立窗口无阴影捕获
│       ├── SelectionOverlay.swift # 多显示器全屏遮罩窗口、模式切换、窗口悬停检测与选区交互视图
│       ├── ScrollingCapture.swift # 滚动长截图悬浮控制面板、定时采样防抖与后台异步拼接调度
│       ├── Editor.swift           # 8 种标注渲染画布、命中检测、拖拽平移、撤销栈、合成导出与编辑器窗口
│       ├── PinnedImage.swift      # 置顶贴图悬浮面板（NSPanel）、透明度切换与右键菜单
│       └── HotKey.swift           # Carbon 全局热键注册（RegisterEventHotKey）与快捷键录制输入框
└── Tests/
    ├── SnipCoreTests/             # 几何换算、选区调整状态机、长图偏移匹配与像素级拼接单元测试
    └── SnipXTests/                # 选区视图确认流、画布缩放拖拽、光标反馈、撤销导出与工具栏布局测试
```
