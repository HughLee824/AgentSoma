# 最小 CLI 与会话宿主验收

**2026-09-05，通过第 2 阶段验收。** Swift CLI 的 connect 在就绪后返回，独立命令通过本地 Unix socket 复用后台宿主与同一个 iPhone Runner。显式断开及空闲到期均正常关闭本会话资源。

环境沿用 macOS 15.0.1、Xcode 16.0 / Swift 6.0、iPhone 12 Pro / iOS 26.6。没有升级工具链，也没有使用 iproxy、pymobiledevice3 或 WDA。

## 实现范围

- 同一 Swift 可执行文件提供 CLI 和内部宿主入口；Foundation Process 管理 xcodebuild，Network.framework 提供 Unix IPC 与 CoreDevice IPv6 通信。
- 提供 connect、status、open、disconnect，运行结果为单行 JSON。connect 使用 `--xctestrun` 指向已签名构建；后续 [build-runner](onboarding.md) 已提供该产物路径。
- 每次连接重新发现 CoreDevice 地址，并按规范 UDID 加文件锁；不同设备别名不能绕过同一状态目录内的重复连接检查。
- 默认空闲 1800 秒，可以调整。就绪和有效命令完成后开始计时；已接收、排队与执行中的命令不被空闲回收。status 仅健康检查，不续期；目前没有额外后台保活轮询。
- 所有设备请求串行处理；开始清理后停止接收新请求，等待已经接收的命令结束。断开完成或到期后删除 socket、退出宿主，旧 session 不再可用。
- open 激活已运行的 App，未运行时启动。参数拒绝为 not_dispatched；正常完成为 completed；派发后丢失响应或缺少精确执行阶段的 Runner 错误保守归为 unknown，不重发。

Runner 只增加宿主管理生命周期模式，在该模式下关闭实验的固定 900 秒上限；空闲计时没有移到设备端。独立旧探针仍保留该上限。

入口及构建命令见 [README](../README.md)。关键实现为 [会话宿主](../Sources/AgentSomaCore/SessionHost.swift)、[生命周期](../Sources/AgentSomaCore/Lifecycle.swift)、[XCTest 适配](../Sources/AgentSomaCore/XCTestBackend.swift) 和 [CLI](../Sources/AgentSoma/AgentSoma.swift)。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| 本地测试 | 10 项通过、0 失败；覆盖真实 Unix IPC、设备锁、执行中 / 排队命令、断开等待、空闲回收、健康检查不续期、参数拒绝及 unknown 不重发。 |
| 默认配置与后台存活 | connect 返回 `idleTimeoutSeconds=1800`，随后不同 CLI 进程复用宿主 PID 79849、Runner PID 8795 和原 Runner session。 |
| 同设备重复连接 | 已用 UDID 占用设备后，再用 CoreDevice ID 连接，返回 device_busy；原会话继续可用。 |
| 有效命令续期 | open Fixture 返回 completed，后续 status 显示剩余时间回到约 1800 秒。 |
| 显式断开 | disconnect 返回成功、退出码 0；Runner 确认 shutdown，xcodebuild 退出码 0，无强制终止。 |
| 受控空闲回收 | 新会话设为 8 秒，约 4 秒后 open 续期；跨过最初 8 秒期限后仍使用原 Runner PID 8794。续期后持续健康检查，约 8.24 秒检测到到期，没有被健康流量续期。 |
| 到期清理 | 自动发送 shutdown，xcodebuild 正常退出；退出原因 idle_timeout。 |
| 资源与失效 | 两轮的宿主 / xcodebuild 均退出，设备进程查询确认 Runner PID 8794、8795 均不存在；socket 删除，旧 session 的 open 返回 not_dispatched。 |
| XCTest 结果 | 显式断开与空闲回收分别为 1 passed / 0 failed / 0 skipped。 |

本地慢命令测试把空闲期限设为 0.4 秒，命令执行超过期限仍未回收，命令完成后重新计时。排队与关闭的精确边界同时使用受控时钟验证，避免用真实长等待代替状态检查。

真机没有等待完整 30 分钟；1800 秒默认配置和缩短时间后的回收行为分别经过验证。当前结果不构成任意时长、物理断线、锁屏或 SIGKILL 后恢复的承诺。

## 证据

本轮文件保存在 Git 忽略的 [验收目录](../spikes/ios-xctest/evidence/cli-host-20260905-01/)：

- [核验汇总与最终源码哈希](../spikes/ios-xctest/evidence/cli-host-20260905-01/verification.json)、[本地测试日志](../spikes/ios-xctest/evidence/cli-host-20260905-01/local-tests.log)。
- [显式断开命令与结果](../spikes/ios-xctest/evidence/cli-host-20260905-01/default-verification.json)、[空闲回收命令与结果](../spikes/ios-xctest/evidence/cli-host-20260905-01/idle-verification.json)。
- [显式断开 XCTest 汇总](../spikes/ios-xctest/evidence/cli-host-20260905-01/default-xcode-summary.json)、[空闲回收 XCTest 汇总](../spikes/ios-xctest/evidence/cli-host-20260905-01/idle-xcode-summary.json)。

该目录还保留两轮 xcodebuild 日志、xcresult、非秘密启动配置及退出记录。运行时 token 不写入会话配置或 CLI 输出。

## 接下来

进入第 3 阶段：在宿主实现紧凑 observe、缓存快照、inspect 和引用失效规则。完整动作执行阶段、任意已安装 App、设备/App 发现和首次构建引导随后完成；当前临时 Runner 仍仅允许 Fixture 与 Calculator。见 [实现计划](v0.1-plan.md)。
