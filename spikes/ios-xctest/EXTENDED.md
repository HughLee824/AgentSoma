# WebView、弹窗与通信恢复验证

2026-09-04，在原有 **Xcode 16.0 + iPhone 12 Pro / iOS 26.6** 环境完成本轮验证。继续使用自有 XCTest Runner，没有引入 WDA 或升级工具链。

| 验证点 | 本轮结果 | 证据边界 |
| --- | --- | --- |
| 指令转发中断后恢复 | 重建 Mac 转发后，原会话 UUID 与 Runner PID 不变，可继续观察和点击 | 主动停止 iproxy；未物理拔掉 USB，也未中断 XCTest 管理连接 |
| 响应丢失时的动作结果 | Mac 收到 0 字节，但点击已把 Count 0 变成 1；重新观察后再发新动作，变成 2 | 没有重发丢失响应的请求；恢复由外部调用方完成 |
| WebView | 坐标点击、按名称与类型点击、中英文输入、JavaScript 回显均通过 | Fixture 内本地 WKWebView；不代表所有网页或混合 App |
| 原生弹窗 | 看到了确认弹窗，坐标点击 Confirm 后弹窗消失，状态变为 Confirmed | App 自己的 SwiftUI alert；系统权限另见下项 |
| 系统通知权限弹窗 | 读取系统弹窗，点击 Don't Allow，系统权限状态变为 denied，弹窗消失 | 一个通知权限拒绝流程；未扩展其他权限种类 |
| pymobiledevice3 启动 | 已解锁前提下，四项核心 XCTest 全部通过，计划正常结束，无初始化错误 | 构建、签名和锁屏预检仍使用 Xcode 工具；不代表脱离 Xcode 的完整安装流程 |

## 通信中断与不确定结果

会话 A：`1F5756DB-D29C-444F-BE46-D2F8CE13B01F`，Runner PID `8155`。

1. 观察确认 `Count: 0`，发送 Increment 点击。
2. 发送后 150 毫秒，停止本轮启动器记录的 iproxy 进程。客户端收到 EOF、0 字节，转发端口拒绝连接。
3. 重建同一设备的转发，ping 返回原会话 UUID、原 PID。
4. 重新观察得到 `Count: 1`。发送一次新的点击，得到 `Count: 2`。

因此，**客户端没有收到成功响应，并不代表设备没有执行动作**。当前工具不会自动重放请求。未来接口需要表达“结果未知”，由调用方重新观察、核对结果；请求去重及自动恢复尚未实现。

会话 A 共处理 20 条请求，客户端保存 19 条响应；第 4 条响应故意丢失，另外有 3 条定位错误。所有收到的响应保持相同 UUID 与 PID，最终显式 shutdown，XCTest 为 1 passed / 0 failed。

- [故障注入记录](evidence/live-20260904T145703Z/fault-injection.json)、[恢复检查](evidence/live-20260904T145703Z/recovery.json)、[完整核验](evidence/live-20260904T145703Z/verification.json)。
- [恢复后 Count 1](evidence/live-20260904T145703Z/006-observe.png)、[下一次点击 Count 2](evidence/live-20260904T145703Z/008-observe.png)、[XCTest 摘要](evidence/live-20260904T145703Z/xcode-summary.json)。

## WebView 与定位边界

[ExtendedProbes.swift](Fixture/ExtendedProbes.swift) 在 Fixture 中加载本地 HTML，使用不持久化的 WKWebView 数据存储；没有访问网页或用户账号。

实际 AX 数据中，HTML 的 `id="web-input"` 没有成为 XCTest identifier。输入框的 identifier 为空，label 为 `Web input`，type 为 49；同名标签也存在，因此仅按名称查询得到 3 个匹配。最初两次输入分别返回 `element_match_count_0`、`element_match_count_3`，没有输入文本。

为验证这一缺口，在现有定位指令中添加可选 `elementType`，继续要求唯一匹配。重建并启动会话 B 后，以下指令通过：

```json
{"op":"type","identifier":"Web input","elementType":49,"text":"Web hello 你好"}
{"op":"tap","identifier":"Web increment","elementType":9}
```

输入后的快照同时包含输入框值 `Web hello 你好` 和 JavaScript 更新的 `Web value: Web hello 你好`；点击后的快照为 `Web count: 1`。输入截图已人工核对；键盘遮挡了下方网页回显，因此回显以 AX 数据为证据，不能把截图未显示的内容说成可见。

会话 B：`8B19AFF1-AF97-4317-B9FD-E37039B0B4B5`，Runner PID `8189`。9 条请求全部成功并正常结束，XCTest 为 1 passed / 0 failed。一次输入含聚焦耗时约 1.56 秒，按钮点击约 0.84 秒，仅为本机单次样本。

- [输入结果及网页回显](evidence/live-20260904T150828Z/006-observe.json)、[输入截图](evidence/live-20260904T150828Z/006-observe.png)、[按钮计数结果](evidence/live-20260904T150828Z/008-observe.json)。
- [会话 B 核验](evidence/live-20260904T150828Z/verification.json)、[XCTest 摘要](evidence/live-20260904T150828Z/xcode-summary.json)、[构建日志](evidence/selector-build.log)。

当前参数仍沿用实验名 `identifier`，实际使用的 XCTest 查询也会匹配 label。这个名字不是最终产品契约。会话 A 用的是修改前的 Runner，原源码副本与哈希已保存；会话 B 才验证新增的类型过滤。

## 原生弹窗

会话 A 打开 `AgentSoma confirmation` 后，快照包含 Alert 节点、Cancel 和 Confirm。Confirm 在 AX 树中有两个嵌套节点，identifier、type、frame 均相同，按 identifier 查询因此返回 `element_match_count_2`。

调用方核对两节点边界一致后，从快照取中心坐标点击。随后观察确认 Alert 消失，`dialog-result` 为 `Confirmed`。没有把重复匹配静默改成取第一个。

- [弹窗快照](evidence/live-20260904T145703Z/016-observe.json)、[弹窗截图](evidence/live-20260904T145703Z/016-observe.png)。
- [重复匹配错误](evidence/live-20260904T145703Z/017-tap.json)、[确认后的截图](evidence/live-20260904T145703Z/019-observe.png)。

## pymobiledevice3 完整核心用例

[run.py](run.py) 增加了启动前锁屏检查与独立的时间戳证据目录。当前设备不支持 pymobiledevice3 的 CoreDevice `get_lockstate()` 调用，返回该 action 未实现；改用本机 `devicectl device info lockState`。锁屏时检查明确拒绝启动，用户解锁后读取到 `passcodeRequired: false` 才执行测试。

| 核心用例 | 结果 | 用例耗时 |
| --- | --- | --- |
| 观察与点击 | Count 1 | 9.70 秒 |
| 中英文输入 | AgentSoma hello 你好 | 12.31 秒 |
| 滑动 | Row 39 到达滚动区域内 | 23.94 秒 |
| 计算器 | 截图及元素树确认 2 + 3 = 5 | 25.47 秒 |

完整调用约 72.22 秒。XCTest 回调为 4 passed、1 skipped、0 failed，额外 skipped 是不带会话 token 的持续会话用例。原统计代码要求回调总数恰好为 4，因而把这次运行误记为 `not_passed`、退出码为 1。现已修正为精确校验四个核心用例，并仅容许该额外用例为 skipped；11 个本地断言覆盖缺失、重复、失败、意外跳过、初始化错误等情况。

原始运行结果与日志保持原样，修正后的判定单独记录在 verification.json。修复统计后没有重复真机运行；四项测试通过的结论来自本次设备回调与导出证据。

- [锁屏时拒绝启动](evidence/pmd-20260904T145626Z/result.json)、[解锁后的原始结果](evidence/pmd-20260904T150445Z/result.json)。
- [汇总修正与回归检查](evidence/pmd-20260904T150445Z/verification.json)、[XCTest 回调日志](evidence/pmd-20260904T150445Z/xctest.log)。
- [计算器结果截图](evidence/pmd-20260904T150445Z/device/AgentSomaEvidence/calculator-result.png)、[本轮设备证据](evidence/pmd-20260904T150445Z/device/AgentSomaEvidence/fixture-text.json)。

这补齐了早先因锁屏而失败的核心套件验证，不能据此解释第一次初始化失败的原因。本轮没有验证通过 pymobiledevice3 启动带 token 的动态会话。

## 系统通知权限弹窗

用户将其余验证项降为低优先级后，仅追加了这一项。2026-09-04 会话 `70A7F01B-7EA0-4534-813D-095640C92EC8`、Runner PID `8282` 验证通过：

1. Fixture 查询系统通知设置，初始显示 `Notifications: notDetermined`。
2. 调用 `UNUserNotificationCenter.requestAuthorization`，真实系统弹窗出现，标题为 `“AgentSoma Probe” Would Like to Send You Notifications`。
3. Runner 从 `com.apple.springboard` 的 Alert 读取 38 个 AX 节点和 1170×2532 截图，包含 `Don’t Allow`、`Allow` 两个按钮。
4. 外部发送按名称与按钮类型定位的 `Don’t Allow` 点击。Fixture 再次查询系统设置，显示 `Notifications: denied`。
5. 再查系统 Alert，返回预期的 `system_alert_count_0`，确认弹窗消失；随后正常 shutdown。

本轮新增 `scope: "systemAlert"`，仅对当前实验 Fixture 的 `observe`、`tap` 开放，观察根节点限定为唯一系统 Alert。没有启动 SpringBoard，也没有配置自动选择权限的 interruption handler；按钮选择来自 Mac 显式指令。系统弹窗观察约 303 毫秒，点击约 1.00 秒，均为单次样本。

```json
{"op":"observe","scope":"systemAlert"}
{"op":"tap","scope":"systemAlert","identifier":"Don’t Allow","elementType":9}
```

10 条请求中 9 条成功，另 1 条是弹窗消失后的预期无弹窗结果；同一 Runner、同一会话贯穿始终。XCTest 为 1 passed / 0 failed，启动器退出 0，转发端口已关闭。测试 App 的通知权限目前为 denied；再次直接请求不会重现首次询问，本轮没有重置其他 App 的权限，也没有发送或安排通知。

- [系统弹窗截图](evidence/live-20260904T152254Z/006-observe.png)、[系统弹窗快照](evidence/live-20260904T152254Z/006-observe.json)、[显式点击请求](evidence/live-20260904T152254Z/007-tap.json)。
- [拒绝后的截图](evidence/live-20260904T152254Z/008-observe.png)、[完整核验](evidence/live-20260904T152254Z/verification.json)、[XCTest 摘要](evidence/live-20260904T152254Z/xcode-summary.json)。
- API 依据：Apple 的 [通知授权状态](https://developer.apple.com/documentation/usernotifications/unnotificationsettings/authorizationstatus) 与 [UI interruption 说明](https://developer.apple.com/documentation/xctest/handling-ui-interruptions)。预期出现的弹窗应作为显式测试步骤处理。

## 对下一步的影响

现有证据支持继续把自有 Swift XCTest Runner 作为无 WDA 后端候选，开始明确外部 agent 所需的 session、observe、action 接口。生产选型仍由用户决定；Python 启动器继续只是实验工具。

按用户最新优先级，本阶段技术验证到此结束。物理 USB 拔插、锁屏/崩溃恢复、更多 App/设备及其他边界测试保留为低优先级限制，不继续扩展，也不阻塞后续产品讨论。元素定位、快照新鲜度及结果未知的语义可在接口设计时依据已有证据明确。

上述三个原生会话均显式关闭，启动器退出 0；相关 iproxy 和 native tunnel 已关闭，Mac 的 47821 转发端口已确认关闭。测试 App 保留以便复用。证据、签名产物和会话 token 继续位于 Git 忽略的目录中。
