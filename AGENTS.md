# AGENTS.md

本文档为在 `SnipX` 仓库中工作的 AI 编程助手提供架构地图、工程命令、核心不变量与开发规范。修改代码前请先阅读对应约束。

---

## 1. 项目概览与技术栈

- **产品形态**：macOS 原生菜单栏截图、标注编辑、滚动长截图与桌面置顶贴图应用（Bundle ID：`com.snipx.app`，菜单栏常驻 `LSUIElement = true`）。
- **构建系统**：Swift Package Manager（`swift-tools-version: 6.0`，语言模式 `swiftLanguageModes: [.v5]`）。
- **平台要求**：macOS 14.0+（`platforms: [.macOS(.v14)]`），`scripts/build.sh` 默认构建 `arm64` Release 包；在 macOS 15.0+ 上启用 `NSCursor.frameResize` 原生缩放光标增强。
- **技术约束**：**零第三方依赖**，纯系统原生框架（`AppKit`、`ScreenCaptureKit`、`Carbon`、`CoreImage`、`CoreGraphics`、`ServiceManagement`、`UniformTypeIdentifiers`）。所有界面均通过纯代码（Auto Layout / `NSStackView` / 自定义 `NSView`）构建，不使用 SwiftUI、Storyboard 或 XIB。

---

## 2. 常用构建、测试与打包命令

```bash
# 编译 Debug 目标
swift build --scratch-path .build

# 运行全量单元测试（SnipCoreTests + SnipXTests）
swift test --scratch-path .build

# 按测试类名或方法名过滤运行单测
swift test --scratch-path .build --filter AdjustableSelectionTests
swift test --scratch-path .build --filter EditorTests/testMoveAnnotationsAndPanAtDifferentZooms

# 构建 Release 并打包签名生成 dist/SnipX.app（默认使用 '-' 进行 ad-hoc 签名）
./scripts/build.sh

# 构建 Release DMG 安装镜像 dist/SnipX-<version>.dmg（推送 v* 标签时由 .github/workflows/release.yml 自动触发并发布到 GitHub Releases）
./scripts/build-dmg.sh

# 使用指定证书签名打包
SIGNING_IDENTITY="Developer ID Application: ..." ./scripts/build.sh

# 启动冒烟测试（验证 App 启动并写入系统版本至 /private/tmp/snipx-smoke.txt，2 秒后自动退出）
dist/SnipX.app/Contents/MacOS/SnipX --smoke-test
```

---

## 3. 模块边界与职责划分

仓库严格拆分为两个 Target，新增功能时必须遵守依赖方向（`SnipX` → `SnipCore`）：

### `Sources/SnipCore`（纯逻辑核心层）
- **严格禁令**：仅允许 `import Foundation` 与 `import CoreGraphics`，**严禁引入 `AppKit`、`ScreenCaptureKit` 或任何窗口/UI 状态**，确保纯计算逻辑可独立、快速、确定性地进行单元测试。
- **文件职责**：
  - `Geometry.swift`（`CaptureGeometry`）：两点框选矩形生成与边界裁剪、AppKit 全局坐标到 Quartz 坐标转换、屏幕点（Point）矩形到 Retina 整数像素（Pixel）矩形换算。
  - `AdjustableSelection.swift`（`AdjustableSelection`）：值类型选区交互状态机，管理创建（`.create`）、平移（`.move`）、8 控制柄缩放（`.resize(Handle)`）及键盘微调（`nudge`）。有效选区最小尺寸为 `8 × 8` pt，控制柄命中半径为 `±7` pt（四角优先级高于四边）。
  - `ScrollMatcher.swift`（`GrayFrame`、`ScrollMatch`、`ScrollMatcher`、`ImageStitcher`）：
    - `GrayFrame`：将 `CGImage` 水平降采样至 `min(96, width)` 的 8-bit 灰度像素数组（保留原始高度与自上而下行序），符合 `Sendable`。
    - `ScrollMatcher`：判定重复帧（`offset = 0` 平均像素差 `< 0.65`），在 `2...(height * 3 / 4)` 范围内抽样搜索最佳纵向滚动偏移（要求 `best < 7.0`，且距离最佳偏移 `> 5 px` 的次优解需满足 `alternate > best + 1.4` 以拒绝周期性重复图案猜测）。
    - `ImageStitcher`：在 sRGB `CGContext` 中将新帧底部新增的 `offset` 行像素无缝拼接到基准图下方，硬性上限为 `maximumHeight = 30_000`、`maximumPixels = 80_000_000`。

### `Sources/SnipX`（macOS 应用与交互层）
- `App.swift`（`SnipXMain`、`AppDelegate`）：应用入口（`.accessory` 激活策略）、状态栏菜单、多实例 `EditorController` 与 `PinnedImageController` 字典生命周期管理、`busy` / `scrolling` 互斥防重入、设置窗口、`SMAppService.mainApp` 登录项同步及 `--smoke-test` 处理。
- `CaptureService.swift`（`CaptureService`、`DisplaySnapshot`、`SnipError`）：`@MainActor` 封装 `ScreenCaptureKit`。显示捕获自动排除当前进程（`processIdentifier`），独立窗口捕获开启 `ignoreShadowsSingleWindow = true` 与 `.best` 分辨率，隐藏光标。
- `SelectionOverlay.swift`（`SelectionOverlay`、`OverlayWindow`、`SelectionView`）：为每块屏幕创建 `.screenSaver` 层级无边框遮罩窗口展示静态桌面快照；通过 `NSEvent.addLocalMonitorForEvents` 拦截 `Esc`、`Enter`、方向键与 `1`/`2`/`3`/`4`/`Space` 模式切换；在 macOS 14 下自绘双向斜箭头光标以补齐系统斜向缩放光标缺失。
- `ScrollingCapture.swift`（`ScrollingCaptureController`）：悬浮非激活控制面板（`NSPanel`）与 `350ms` 轮询采样循环。
- `Editor.swift`（`AnnotationTool`、`Annotation`、`AnnotationCanvas`、`ImageOutput`、`EditorController`）：8 种标注工具绘制、`CIPixellate` 马赛克缓存、基于描边路径（`copy(strokingWithWidth:)`）的命中检测、左键拖拽标注 / `⌥` 强制新建绘制、右键平移 `NSScrollView`、`⌘Z` / `⇧⌘Z` 历史栈、全分辨率位图扁平化导出（`flattened()`）及剪贴板/文件输出。
- `PinnedImage.swift`（`PinnedImageController`、`PinImageView`）：`.floating` 层级全空间置顶贴图面板，支持背景拖拽、等比缩放、透明度切换（`1.0` / `0.55`）与右键菜单。
- `HotKey.swift`（`HotKey`、`ShortcutField`）：基于 Carbon `RegisterEventHotKey`（签名 `'SNPX'` / `0x534E5058`）的全局热键注册与自定义快捷键录制文本框。

---

## 4. 核心不变量与易错机制（修改必读）

### 4.1 三套坐标系与翻转约定
1. **AppKit 全局屏幕坐标**（`NSScreen.frame`、`NSEvent.mouseLocation`）：原点位于**主屏幕左下角**，Y 轴向上递增。
2. **Quartz / `ScreenCaptureKit` 全局坐标**（`SCWindow.frame`、`CGWindowListCopyWindowInfo`）：原点位于**主屏幕左上角**，Y 轴向下递增。在窗口模式悬停命中检测时，必须使用 `CaptureGeometry.quartzRect(screenFrame, primaryHeight: primaryHeight)` 换算（注意副屏位于主屏上方时 Quartz `y` 为负数，参考 `GeometryTests.testSecondaryScreenAboveMain`）。
3. **视图局部坐标与图像导出**：
   - `SelectionView` 与 `AnnotationCanvas` 均重写了 `override var isFlipped: Bool { true }`（左上角原点，Y 轴向下），从而与 `CGImage.cropping(to:)` 的像素坐标系直接对齐。
   - 在 `AnnotationCanvas.flattened()` 中向 `NSBitmapImageRep` 离屏渲染时，必须先对 `cgContext` 执行 `translateBy(x: 0, y: height)` + `scaleBy(x: 1, y: -1)` 并以 `NSGraphicsContext(cgContext: ..., flipped: true)` 包装，否则导出的图像或标注会发生上下颠倒（由 `EditorTests.testFlattenPreservesResolutionAndOrientation` 守护）。

### 4.2 点（Point）与像素（Pixel）尺度关系
- **`SelectionView`**：`bounds` 为屏幕点尺寸（`screenFrame.size`）。区域裁剪时必须调用 `CaptureGeometry.pixelRect` 转换到快照 `CGImage` 的像素尺寸；而传给 `ScrollingCaptureController` → `CaptureService.capture(display:content:region:)` 的 `region` 保持为**屏幕点尺寸**（赋值给 `SCStreamConfiguration.sourceRect`，输出像素宽高乘以 `filter.pointPixelScale`）。
- **`AnnotationCanvas`**：`bounds` 始终固定为源图像素尺寸（`source.width × source.height`），所有 `Annotation.points` 均以原图像素坐标存储；视图缩放仅调整 `frame`（`frame = bounds * zoom`）。因此在 `annotationIndex(at:)` 中做鼠标命中测试时，容差必须按缩放比例反算（`tolerance = 6 / scale`）。
- **右键拖拽平移画布**：`AnnotationCanvas.rightMouseDragged` 计算拖拽位移时，必须在 `scroll.contentView`（即 `NSClipView`）坐标系中转换鼠标窗口坐标，切勿在随滚动实时改变原点的文档视图坐标系中直接相减。

### 4.3 并发隔离与长截图防抖
- 所有窗口控制器、视图与 `CaptureService` 均运行在 `@MainActor` 上。
- `AppDelegate.beginCapture` 启动时固定等待 `180ms`（`Task.sleep(for: .milliseconds(180))`），确保状态栏菜单完全收起后再冻结桌面快照，避免截入菜单残影。
- `ScrollingCaptureController.consume` 采用**双帧静止判稳**：只有当连续两次采样帧 `pending` 与 `current` 满足 `ScrollMatcher.isDuplicate(pending, current)`（即用户滚动后短暂停稳）时，才在 `Task.detached(priority: .userInitiated)` 中执行 `ScrollMatcher.match` 与 `ImageStitcher.append`，防止滚动过程中的动态模糊或撕裂帧破坏拼接。发生错误（如达到尺寸上限）时须保留已拼接的 `result` 供用户点击「完成」导出。

### 4.4 `.app` 打包形态、签名与系统权限
- 直接运行 `.build/debug/SnipX` 裸可执行文件时，`Bundle.main.bundleURL.pathExtension != "app"`，`AppDelegate.refreshLaunchAtLogin` 会主动禁用开机自启开关；同时 macOS 屏幕录制 TCC 授权和 `LSUIElement` 菜单栏行为均依赖完整的 `.app` Bundle。涉及权限、登录项或菜单栏行为的验证必须通过 `./scripts/build.sh` 生成 `dist/SnipX.app` 测试。
- 开机自启状态**严禁缓存到 `UserDefaults`**，始终以 `SMAppService.mainApp.status` 实时系统状态为准（并在 `applicationDidBecomeActive` 时刷新）。
- 使用默认 Ad-hoc 签名（`-`）重新构建 `dist/SnipX.app` 会改变二进制 CDHash，可能导致系统「屏幕与系统音频录制」已授予的权限失效；本地调试遇到持续提示无权限时，使用 `tccutil reset ScreenCapture com.snipx.app` 重置。

---

## 5. 编码风格与测试约定

- **语言规范**：
  - 所有面向用户的 UI 文本、菜单项、工具提示及 `SnipError` 错误消息统一使用**简体中文**。
  - 代码命名、注释、测试函数名及 Git 提交信息统一使用**英文**，Git 提交遵循 Conventional Commits（如 `feat: ...`、`fix: ...`、`chore: ...`）。
- **代码组织**：保持单文件职责聚焦、精炼紧凑，不为单次调用过度抽象，不引入外部 Package 依赖。
- **编写测试注意事项**：
  - 纯算法、几何变换、选区状态与图像拼接逻辑必须优先放入 `SnipCore` 并在 `Tests/SnipCoreTests/` 中编写无 UI 依赖的单元测试。
  - 在 `Tests/SnipXTests/` 中测试 AppKit 视图/窗口时，测试方法需在 `await MainActor.run` 中执行，先触发 `_ = NSApplication.shared`，对测试创建的 `NSWindow` 显式设置 `window.isReleasedWhenClosed = false` 并配合 `defer { window.close() }` 释放，防止 XCTest 退出时因 AppKit 双重释放崩溃。
  - [EditorTests.swift](Tests/SnipXTests/EditorTests.swift) 中的 `testToolbarLayoutAndGeneratePreview` 会基于 `#filePath` 将预览图输出至仓库根目录下的 `.build/editor-preview.png`（会自动创建父目录，兼容本地与 GitHub Actions CI 环境）。
