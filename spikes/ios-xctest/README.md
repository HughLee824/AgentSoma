# 独立 XCTest Runner 验证

2026-09-04 真机验证通过：自行编写、只调用 Apple XCTest API 的 Runner，在 **Xcode 16.0 + iOS 26.6** 上完成观察、点击、中英文输入、滑动和跨 App 操作。本次验证没有引入 WDA，也没有升级 Xcode。

这是用户已允许的技术可行性实验。生产后端和宿主语言仍未选定。后续的动态指令与持续会话也已在真机通过：同一 Runner 处理 32 条请求，完成 Fixture 和计算器两轮操作，见 [LIVE.md](LIVE.md)。本页保留最初四项固定用例的结果。

最新扩展验证见 [EXTENDED.md](EXTENDED.md)：WebView 中英文输入与点击、原生弹窗、系统通知权限弹窗、通信转发恢复已通过；pymobiledevice3 在明确解锁后也完成了四项核心用例。用户已将其余验证项降为低优先级，本阶段验证到此结束。

## 实测结果

原生 `xcodebuild test-without-building` 返回成功；`xcresulttool` 摘要为 **4 passed / 0 failed**，设备确认为 iPhone 12 Pro / iOS 26.6。

| 能力 | 验证结果 | 原生用例耗时 |
| --- | --- | --- |
| 截图与元素信息、点击 | 点击 Increment，断言并导出 `Count: 1`；保存截图、层级文本、元素属性和边界 | 9.211 秒 |
| 英文和中文输入 | 依次输入并断言 `AgentSoma hello`、`AgentSoma hello 你好`；截图与元素值一致 | 14.886 秒 |
| 滑动 | Row 39 从不可点击变为可点击；截图确认已滚到列表底部 | 23.890 秒 |
| 跨 App 操作 | 启动系统计算器，依次点击 AC、2、+、3、=；截图与层级中的结果文本均为 5 | 25.105 秒 |

四项用例累计 73.092 秒，包含 App 启动、等待、操作和证据导出，**不能作为单次动作延迟**。计算器用例本身断言按钮存在并执行点击；结果为 5 是通过运行后检查截图和元素树确认的。

观察结果包括 1170×2532 PNG、`debugDescription` 层级文本，以及包含 type、identifier、label、value、enabled、frame 的 JSON。当前 JSON 为最多 100 个后代元素的平铺列表，本轮每个快照含 34–46 个元素；它还不是带父子关系、完整性和一致性保证的产品快照协议。当前竖屏窗口为 390×844 点，与截图尺寸比例为 3；其他方向和设备仍需验证。

原生证据：

- [XCTest 结果摘要](evidence/xcode-summary.json)、[执行日志](evidence/xcode-run.log)，完整结果包为 `evidence/xcode-run.xcresult`。
- [点击后的状态](evidence/native-device/AgentSomaEvidence/fixture-tap.json)、[中文输入截图](evidence/native-device/AgentSomaEvidence/fixture-text.png)、[滑动截图](evidence/native-device/AgentSomaEvidence/fixture-swipe.png)。
- [计算器截图](evidence/native-device/AgentSomaEvidence/calculator-result.png)、[计算器元素树](evidence/native-device/AgentSomaEvidence/calculator-result.tree.txt)。计算结果的原始 label 带有 U+200E 方向标记，读取文本时需保留原文并明确规范化规则。

## 两种启动方式

| 启动方式 | 本轮结论 |
| --- | --- |
| Xcode 原生启动 | 明确报告锁屏并等待解锁；用户解锁后四项全部通过，作为当前可复现基线。 |
| pymobiledevice3 11.3.1（早期） | 初次连接 Runner 后 UI 测试初始化失败，未执行用例，当时未保存完整初始化错误。修复错误采集后复测，三个 Fixture 用例被系统以 `Locked` 拒绝启动；计算器用例通过，整体为 1 passed / 3 failed。 |
| pymobiledevice3 11.3.1（解锁预检后） | 四项核心用例全部通过；额外的持续会话用例 skipped，计划正常结束。原汇总把 skipped 计入总数而误报失败，已保留原记录并单独修正判定。详见扩展报告。 |

复测的失败发生在 App 启动阶段，不是点击或输入断言失败。不能仅凭 Runner 进程启动、屏幕亮起，或计算器可以操作，就判断设备满足所有 App 的测试前提；不同 App 的行为需分别验证。现有证据也不能单独确定初次初始化失败的原因。

两次 pymobiledevice3 结果分别保存在 [首次结果](evidence/pmd-first-attempt.json) 和 [复测结果](evidence/pmd-retry-result.json)。复测只新导出了计算器证据，位于 `evidence/pmd-device/`；原生四项证据已提前保存，避免混淆两轮结果。

## 实现范围

- `Fixture/FixtureApp.swift`：本地测试页，提供计数按钮、文本框和滚动列表，不使用用户的文档或账号。
- `Tests/AgentSomaTests.swift`：仅调用 Apple XCTest API，验证点击、英文/中文输入、滑动和跨 App 计算器操作。
- `project.yml`：XcodeGen 探针工程定义，无第三方包依赖；会话测试引用 `../../Runner/LiveSessionTests.swift`，避免维护两份实现。正式 Runner 使用[独立 Xcode 工程与 build-runner](../../docs/onboarding.md)，不需要生成此探针工程。
- `run.py`：实验性的 pymobiledevice3 XCTest 启动器，保留设备初始化错误和用例结果。Xcode 自带的 `test-without-building` 是对照启动路径。

DeviceKit 源码检查采用 `c6a61f406d0b894bfa5864fb950eb5f8f3a20b99`。其中包含带 Facebook 版权声明的 FBConfiguration 及 WDA 相关辅助实现，因此本轮使用自行编写的最小 Runner。DeviceKit 没有被编译、链接或安装。

## 环境与依赖边界

- macOS 15.0.1，Xcode 16.0，iPhone13,3 / iOS 26.6。
- XcodeGen 2.44.1，pymobiledevice3 11.3.1。
- 使用本机既有 Apple Development 证书和覆盖测试手机的有效通配 provisioning profile；未创建证书或请求新的配置文件。
- `build-for-testing` 成功，采用 iPhoneOS 18.0 SDK；Runner 的 `codesign --verify --deep --strict` 通过。
- 已安装 `com.somnus.agentsoma.spike.fixture` 和 `com.somnus.agentsoma.spike.tests.xctrunner`。安装前查询确认这两个 bundle ID 不存在。
- Runner 中嵌入的测试框架均来自 Apple；项目没有第三方包依赖。设备上执行的是本项目生成的 `AgentSomaTests-Runner`。

原始构建日志、签名元数据、结果包和截图都存放在 Git 忽略的 `evidence/`；第三方源码和构建产物同样已忽略。两个实验 App 保留在设备上，供后续验证复用。结束时已确认 Runner 进程退出，并关闭本轮 native tunnel。

## 对技术选型的影响

“完全不依赖 WDA”在本机环境已有正向证据：独立 XCTest Runner 可以提供核心的眼睛和手。后续已以原生启动路径为基线，验证持续会话中的 `observe → tap/type/swipe → observe` 指令往返。自有 Swift XCTest Runner 是证据支持的后端候选，尚不是用户确认的生产选型。

后续已经验证动态指令通道、动作延迟、坐标点击、带父子关系的有界结构化快照，以及转发重建后原会话继续。仍未验证锁屏后恢复、物理 USB 拔插、未知前台 App 的识别、横屏、更多 App 和系统版本、产品快照完整性与一致性保证。当前只有一台手机，以及本地 Fixture（含 WKWebView、原生弹窗）和系统计算器的证据，不能外推为任意已安装 App 均可完成任意任务。

## 复现构建与原生启动

在本目录执行。将 `DEVELOPMENT_TEAM_ID`、`IOS_UDID` 设为本机开发团队和测试设备。既有证书、匹配的有效 profile、Developer Mode 和解锁设备是前提。

```sh
xcodegen generate
xcodebuild build-for-testing -project AgentSomaSpike.xcodeproj -scheme AgentSomaSpike -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM_ID" CODE_SIGN_STYLE=Automatic
xcodebuild test-without-building -xctestrun build/Build/Products/AgentSomaSpike_iphoneos18.0-arm64.xctestrun -destination "platform=iOS,id=$IOS_UDID" -parallel-testing-enabled NO -resultBundlePath evidence/reproduction.xcresult
```

结果包路径每次应使用新名称。不同 Xcode/SDK 会生成不同名称的 `.xctestrun`，应以 `build/Build/Products` 下的实际文件为准。代码签名及设备发现需要允许宿主工具访问 macOS 本机开发服务；受限沙箱中的“没有证书”或设备发现超时不等于本机环境缺失。

测试会在自己的测试页输入文本，并在计算器中清空当前输入后执行 `2 + 3`。它不是 AgentSoma 的产品测试 DSL 或对用户任务的通用规划器。
