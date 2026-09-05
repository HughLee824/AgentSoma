# CoreDevice 原生直连验证

**2026-09-05 真机验证通过。** 使用现有 macOS 15.0.1、Xcode 16.0、Swift 6.0 与 iPhone 12 Pro / iOS 26.6，自有 XCTest Runner 可以通过 CoreDevice 原生 IPv6 通道直接访问，无需 iproxy、pymobiledevice3 或 WDA。

本轮验证的是已确认架构中的设备通信路径；正式 CLI、宿主 IPC、观察引用与空闲回收尚未实现。

后续进展：同日下一阶段已实现最小 CLI / 宿主和空闲回收，并有独立的 [宿主验收记录](../../docs/session-host.md)。本文以下内容保留为前一轮通信探针的证据，不将后续能力计入本轮。

当前 Runner 已接入宿主观察目标校验和执行事实，旧探针的直接动作消息属于历史协议。复现后续操作请使用 [正式 CLI 动作接口](../../docs/actions.md)，本文的原始通信证据保持不变。

## 实际路径与最小改动

`Swift 探针 → Network.framework TCP → CoreDevice IPv6 → 薄 XCTest Runner`

- Mac 探针通过 `xcrun devicectl device info details --json-output` 的 `result.connectionProperties.tunnelIPAddress` 获取当前设备地址。
- Runner 新增 `AGENTSOMA_LISTEN_HOST` 环境变量，只绑定本次发现的具体 IPv6 地址及端口 `47821`。未提供时仍使用旧实验的 `127.0.0.1`；未改为全网卡监听。请求继续使用随机会话 token 认证。
- 自有 Swift 探针用 Foundation `Process` 启动并等待 `xcodebuild test-without-building`，由 Apple 工具管理 XCTest 会话；独立 `call` 进程通过系统 Network.framework 发出一条 JSON 行并接收结果，随后退出。
- Runner 的观察、动作、实验白名单与固定 900 秒上限保持原样。没有把引用管理或空闲策略放进 Runner。

本次使用的地址为 `fd97:fbf3:2b4f::1`，路由接口是 `utun9`，CoreDevice 报告 `transportType: wired`。预检和实际启动曾返回不同地址，因此每次建立会话都要重新发现，不能硬编码或跨会话复用旧地址。地址仅是本次证据。

源码：[Runner](../../Runner/LiveSessionTests.swift)、[Swift 探针](NativeTransportProbe.swift)。探针没有增加源码库或外部设备工具依赖。本轮验证时构建沿用已有 Xcode 工程；后续 Runner 源码已移到独立工程，重新构建旧探针时需按更新后的 project.yml 生成工程。

## 结果

| 检查 | 实测 |
| --- | --- |
| 独立请求复用 | 7 个不同 Mac 客户端进程、7 次独立 TCP 连接；所有响应具有相同会话 UUID `10FC79F0-36F4-4815-B7BC-CA5386A11881` 和 Runner PID `8752`，序号连续 1–7。 |
| 图像与 AX 传输 | 两次观察各返回 37 个节点、有效父子索引及 1170×2532 PNG，未截断；完整网络响应分别为 209,987 和 208,006 字节。 |
| 动作闭环 | 观察 `Count: 0`，点击 `increment`，再次观察得到 `Count: 1`；截图也确认变化。 |
| 命令间隔 | 上一条响应收到后约 60.38 秒无探针请求，下一条 ping 成功，仍是原 Runner。期间没有额外的 devicectl 轮询或探针保活；xcodebuild 的 XCTest 管理会话持续运行。 |
| 正常结束 | shutdown 收到确认，XCTest 为 1 passed / 0 failed / 0 skipped，xcodebuild 和启动探针返回 0；随后查询确认两个 Mac 进程和设备 Runner PID 均已退出。 |
| 依赖边界 | 当前相关进程证据中没有 iproxy、pymobiledevice3 或 tunneld。Apple 的共享设备服务继续由系统管理。 |

两次观察的 Mac 往返耗时分别为 304.49 ms 和 277.82 ms；一次点击为 526.69 ms。这些计时从建立连接前开始，到接收并解析响应结束，不包含 CLI 进程启动、文件保存或 agent 读图。样本不足以形成性能承诺。

证据位于 [本轮目录](evidence/native-coredevice-20260905-01/)：

- [结果核验与源码哈希](evidence/native-coredevice-20260905-01/verification.json)、[XCTest 结构化汇总](evidence/native-coredevice-20260905-01/xcode-summary.json)。
- [点击前观察](evidence/native-coredevice-20260905-01/003-observe.json)、[点击后观察](evidence/native-coredevice-20260905-01/005-observe.json)、[点击后截图](evidence/native-coredevice-20260905-01/005-observe.png)。
- [间隔后的 ping](evidence/native-coredevice-20260905-01/006-ping.json)、[shutdown](evidence/native-coredevice-20260905-01/007-shutdown.json)。
- [设备通道信息](evidence/native-coredevice-20260905-01/device-details.json)、[路由](evidence/native-coredevice-20260905-01/route.txt)、[会话期间进程](evidence/native-coredevice-20260905-01/host-processes-during.txt)、[结束后的 Mac 进程检查](evidence/native-coredevice-20260905-01/host-processes-after.txt)、[设备进程检查](evidence/native-coredevice-20260905-01/device-processes-after.json)。

证据目录为 Git 忽略项。目录权限 0700，含 token 的 `session.json` 权限 0600；不要把它当作公开报告提交。

## 复现

在 `spikes/ios-xctest` 目录操作，先解锁手机、保持 USB 连接；签名使用本机已配置的开发团队。以下为探针命令，并非正式 `agentsoma` 接口。

```sh
xcodebuild build-for-testing \
  -project AgentSomaSpike.xcodeproj -scheme AgentSomaSpike \
  -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build DEVELOPMENT_TEAM=SQ559MFPXF CODE_SIGN_STYLE=Automatic

xcrun swiftc -swift-version 5 -module-cache-path build/native-module-cache \
  NativeTransportProbe.swift -o build/native-probe

build/native-probe start "$PROBE_SESSION_DIR" "$IOS_UDID"
```

`PROBE_SESSION_DIR` 必须是一个尚不存在的目录。启动器持续运行并将日志写到该目录的 `xcodebuild.log`；看到 `AGENTSOMA_LIVE_READY` 后，从另一个命令进程调用：

```sh
build/native-probe call "$PROBE_SESSION_DIR" '{"op":"ping"}'
build/native-probe call "$PROBE_SESSION_DIR" '{"op":"launch","bundleId":"com.somnus.agentsoma.spike.fixture"}'
build/native-probe call "$PROBE_SESSION_DIR" '{"op":"observe"}'
build/native-probe call "$PROBE_SESSION_DIR" '{"op":"tap","identifier":"increment"}'
build/native-probe call "$PROBE_SESSION_DIR" '{"op":"observe"}'
# 留出至少 30 秒命令间隔，再继续。
build/native-probe call "$PROBE_SESSION_DIR" '{"op":"ping"}'
build/native-probe call "$PROBE_SESSION_DIR" '{"op":"shutdown"}'
```

`call` 保存完整 JSON 和 PNG，stdout 输出精简的探针摘要；连接错误、EOF 或超时均不自动重发。首次编译安装与等待人工解锁不属于热调用时间。本轮沙箱内的 CoreDeviceService 初始化超时，允许访问主机设备服务后立即成功；这不是手机不兼容。

## 对实现计划的影响

第一个通信验证已通过，可以进入最小 Swift CLI 与会话宿主实现。当前证据支持在这套工具链上使用原生 CoreDevice 通信和 xcodebuild 启动，不需要增加第三方转发工具或升级 Xcode。

60 秒间隔是在 xcodebuild 持有 XCTest 会话期间验证的，不能外推为任意长时间的通道稳定性，也不能证明没有 XCTest 管理会话时通道仍保留。正式的 30 分钟空闲策略、宿主后台启动与 IPC、异常退出清理、引用和动作结果契约仍按产品计划实现。物理重连、锁屏恢复及更广系统覆盖继续保持原优先级。
