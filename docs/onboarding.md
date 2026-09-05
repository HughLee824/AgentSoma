# Runner 构建与首次接入

v0.1 使用本机 Mac/Xcode 和用户自己的开发签名。外部 agent 执行构建、连接及设备命令；登录 Apple 账号、首次信任和系统确认由用户完成。

## 准备一次签名环境

1. 使用完整 Xcode；`xcode-select -p` 应指向该 Xcode 的 `Contents/Developer`。如果选择了独立 Command Line Tools，可在 Xcode 的 Settings → Locations 中选择工具链。
2. 在 Xcode 登录自己的 Apple 开发账号，打开 `Runner/AgentSomaRunner.xcodeproj`。选择 `AgentSomaTests` target，在 Signing & Capabilities 中选择团队、启用自动签名，并设置该团队可使用的 bundle ID。默认 `com.agentsoma.runner` 是工程默认值，可按账号需要更改。
3. 用 USB 连接 iPhone，完成设备上的信任确认并启用 Developer Mode；保持解锁。首次证书/profile 配置需要时，在 Xcode 选择该设备和 `AgentSomaRunner` scheme，使用 Product → Build For → Testing 完成签名配置。

CLI 不管理 Apple 账号、证书或 profile，不传入 `-allowProvisioningUpdates`。团队和 bundle ID 可以保存在本机 Xcode 工程设置中，也可由 agent 在构建时用 `--team`、`--bundle-id` 覆盖。命令行覆盖不会写回 Xcode 工程。

## 由 agent 构建并连接

在 AgentSoma 源码目录执行：

```sh
swift build
.build/debug/agentsoma build-runner --team "$APPLE_TEAM_ID"
```

已经在 Xcode 工程中选择团队时，省略 `--team`。当 agent 的当前目录是待测 App 项目时，使用 AgentSoma CLI 的完整路径，并传 `build-runner --source-root /path/to/AgentSoma`。

成功返回单行 JSON，路径以实际输出为准：

```json
{"ok":true,"result":{"xctestrun":"/path/to/AgentSoma/.build/runner/<build-id>/Build/Products/AgentSomaRunner_iphoneos18.0-arm64.xctestrun","runnerApp":"/path/to/AgentSoma/.build/runner/<build-id>/Build/Products/Debug-iphoneos/AgentSomaTests-Runner.app","buildDirectory":"/path/to/AgentSoma/.build/runner/<build-id>","log":"/path/to/AgentSoma/.build/runner/<build-id>/build.log"}}
```

`build-runner` 调用 Apple `xcodebuild build-for-testing` 和 `codesign --verify --deep --strict`。它从产物目录读取真实 `.xctestrun` 名称及 Runner 路径，不硬编码 SDK 版本。构建日志保存在 `build.log`，路径清单同时保存到 `build.json`；失败返回非零退出码和 JSON 错误。Apple 对构建与后续测试命令的说明见 [TN2339](https://developer.apple.com/library/archive/technotes/tn2339/_index.html)。

```sh
.build/debug/agentsoma devices
.build/debug/agentsoma connect --device "$IOS_UDID" --xctestrun "$SIGNED_XCTESTRUN"
# 使用 connect 返回的 session。
.build/debug/agentsoma --session "$SESSION" apps --query Settings
.build/debug/agentsoma --session "$SESSION" open com.apple.Preferences
.build/debug/agentsoma --session "$SESSION" observe
# agent 读取 observe 返回的 PNG，再根据实际观察选择动作。
.build/debug/agentsoma --session "$SESSION" disconnect
```

`SIGNED_XCTESTRUN` 使用构建结果的 `result.xctestrun`。`connect` 用 Xcode 安装并启动 Runner；之后继续使用已验证的 CoreDevice 原生链路。断开会话停止进程并释放观察缓存，签名构建和手机上的 Runner 保留以便复用。

每次构建分配一个新的目录，避免覆盖活跃会话引用的文件。源码、Xcode 或签名发生变化后重新构建，并将新路径用于下一次 connect。相同构建可供后续会话复用；不需要每次连接都编译。构建目录暂时不自动清理，确认没有会话引用后可移除不再需要的目录。上述独立目录、CLI 名称与路径字段是工程实现选择。

## 常见接入错误

| 返回结果 | 下一步 |
| --- | --- |
| `runner_source_missing` | 将 `--source-root` 指向包含 `Runner/AgentSomaRunner.xcodeproj` 的源码目录。复制单个 CLI 二进制不会携带 iOS 源码。 |
| `invalid_team` / `invalid_bundle_id` | 修正签名参数；team 是 10 位开发团队 ID，bundle ID 是点分隔标识。 |
| `runner_build_failed` | 阅读返回路径中的 `build.log`。若提示缺少开发团队/profile，在 Xcode 完成签名；若选中的是 Command Line Tools，切换到完整 Xcode。构建错误不一概归因于签名。 |
| `runner_products_invalid` / `runner_signature_invalid` | 检查当前源码、构建日志和产物；重新构建，使用新的输出路径。 |
| `device_locked` | 解锁手机后重新 connect。 |
| `runner_start_failed` / `coredevice_unavailable` | 查看返回的会话日志，核对设备信任、Developer Mode、USB 和开发服务状态。构建成功不等于设备侧安装或启动已成功。 |

## 工程边界

`Runner/LiveSessionTests.swift` 是原有会话 Runner 的同一实现；独立原生 Xcode 工程只编译该文件，没有 Fixture 依赖或额外固定测试。测试模块仍叫 `AgentSomaTests`，以保持现有宿主选择器兼容。旧探针的 `project.yml` 引用同一源码；重建探针前重新运行 XcodeGen。正式 Runner 构建不需要它。

这完成的是已有 Mac/Xcode 签名条件下的源码接入。免 Xcode 安装、全新 Mac 配置、免费 Personal Team 签名以及更多 OS/设备组合仍未验证；iOS 16 和 macOS 13 的编译部署下限不是完整链路的支持承诺。

## 2026-09-05 验收

代码提交 `2c5019d`；环境为 macOS 15.0.1、Xcode 16.0 / Swift 6.0、iPhone 12 Pro / iOS 26.6。沿用已有开发证书和 profile，没有升级 Xcode 或申请新的签名资源。

| 检查 | 结果 |
| --- | --- |
| 本地测试 | 33 项通过，新增 4 项覆盖签名参数边界、缺失源码、实际 SDK 文件名、两种 manifest 布局、缺失/歧义/错误产物。 |
| 独立构建 | 指定既有测试 bundle ID 和使用默认 bundle ID 的两次签名构建均成功。默认构建从仅包含 Runner 的干净副本完成，源码路径含空格，CLI 从 `/private/tmp` 调用。构建未使用 XcodeGen。 |
| 签名未配置 | 省略团队且工程未配置团队时，CLI 退出 1，返回 `runner_build_failed` 与包含缺少开发团队原因的日志路径；失败构建使用另一独立目录。 |
| 产物 | manifest 的 `UseUITargetAppProvidedByTests=true`，依赖只有 Runner.app 与内嵌测试 bundle，没有 `UITargetAppPath` 或 Fixture。源码副本与提交的 Runner 文件逐字节相同。 |
| 首次安装及操作 | 安装前原生清单没有 `com.agentsoma.runner.xctrunner`；connect 后清单确认存在，且这是唯一新增 bundle ID。8 次独立 CLI 调用完成连接、安装确认、打开设置、观察、引用点击返回、再观察、status 与 disconnect。 |
| 结果与清理 | 两张 1170×2532 截图均由调用 agent 实际读取，AX 和图片确认 General → Settings，未改动设置值。复用 Runner PID 8930 / UUID `62CE2CCD-B534-4C0B-B55E-C2E65E465C04`，XCTest 1 通过、0 失败、0 跳过。宿主 4136、xcodebuild 4142 与设备 Runner 均已退出，socket/观察缓存删除，没有强制终止。 |

Settings 两次采集都如实报告 200 节点的源截断；没有将其视为完整 AX。构建产物和已安装 Runner 保留供后续会话使用。本次没有重新执行此前已通过的输入/弹窗矩阵；旧探针仅重新生成工程，确认共享源码引用有效。

本机证据位于 Git 忽略目录 `spikes/ios-xctest/evidence/onboarding-20260905-01/`：

- [汇总与源码哈希](../spikes/ios-xctest/evidence/onboarding-20260905-01/verification.json)、[8 次 CLI 原始结果](../spikes/ios-xctest/evidence/onboarding-20260905-01/commands.json)。
- [默认构建路径](../spikes/ios-xctest/evidence/onboarding-20260905-01/build.json)、[构建日志](../spikes/ios-xctest/evidence/onboarding-20260905-01/build.log)、[缺少签名配置的结果](../spikes/ios-xctest/evidence/onboarding-20260905-01/missing-signing.json)。
- [General 截图](../spikes/ios-xctest/evidence/onboarding-20260905-01/o1.png)、[返回后的 Settings 截图](../spikes/ios-xctest/evidence/onboarding-20260905-01/o2.png)。同目录含原始快照、安装前后清单、进程清理记录与完整 `run.xcresult`。
- [XCTest 摘要](../spikes/ios-xctest/evidence/onboarding-20260905-01/xctest-summary.json)、[本地测试日志](../spikes/ios-xctest/evidence/onboarding-20260905-01/swift-tests.log)。
