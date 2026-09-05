# 持续 XCTest 会话实验

本轮验证同一个 Runner 进程能否接收 Mac 动态发送的指令，并在操作之后返回可核对的界面信息。使用现有 Xcode 16、iOS 26.6 和自有 XCTest 代码；生产宿主语言与 MCP 接口仍未选定。

**2026-09-04 真机验证通过。** 一个 Runner 会话连续处理 32 条 Mac 动态请求，包含 31 条成功请求和 1 条预期的不存在元素错误。两轮操作之间没有编译、重启 XCTest 或更换 Runner；原生 XCTest 最终为 1 passed / 0 failed。

后续已补充 WebView、原生弹窗、系统通知权限弹窗、转发中断后恢复，以及 pymobiledevice3 四项核心用例通过的证据，见 [EXTENDED.md](EXTENDED.md)。以下主会话数据保持原样。

2026-09-05 又完成了无需 iproxy / pymobiledevice3 的 [CoreDevice 原生直连验证](NATIVE.md)，并已确认产品采用 Swift CLI 与按会话运行的宿主。本文的 Python/iproxy 路径和未选型描述保留为历史实验记录。

## 结果与证据

主会话 `FFED37E9-D61F-4A8D-9AEA-A5B197ED3F16`，Runner PID `8127`，请求序号连续为 1–32，全部响应保持相同会话 ID 和 PID。源码哈希在会话前后相同。

| 验证 | 实际结果 |
| --- | --- |
| 第一轮：Fixture | 从快照取得 Increment 中心点 `(195, 209.17)`，坐标点击后 Count 0→1；输入 `AgentSoma live 你好` 并回读；三次滑动后观察到 Row 39 完整位于滚动区域内。 |
| 错误后继续 | 不存在的 identifier 返回 `element_match_count_0`；下一次观察计数仍为 1；正常点击后变为 2，会话继续。 |
| 第二轮：计算器 | 启动系统计算器，外部逐条发送点击与观察，结果依次为 `0 → 7 → 7× → 7×8 → 56`。 |
| 观察数据 | 15 次截图与快照，1170×2532 PNG；节点 index/parent 关系检查通过，所有快照均未触发 200 节点截断。 |
| 结束 | 显式 `shutdown` 得到确认，XCTest 用例通过，Mac 启动器返回 0 并关闭 USB 转发。 |

关键证据：

- [统计摘要](evidence/live-20260904T143332Z/summary.json)、[结果核验](evidence/live-20260904T143332Z/verification.json)、[XCTest 摘要](evidence/live-20260904T143332Z/xcode-summary.json)。
- [坐标点击后的 Count 1](evidence/live-20260904T143332Z/005-observe.png)、[中英文输入](evidence/live-20260904T143332Z/009-observe.png)、[滑动到 Row 39](evidence/live-20260904T143332Z/015-observe.png)。
- [预期错误](evidence/live-20260904T143332Z/016-tap.json)、[错误后继续点击](evidence/live-20260904T143332Z/019-observe.json)、[计算器 56 截图](evidence/live-20260904T143332Z/031-observe.png)。

主会话用例持续 316.276 秒，包含外部调用方阅读、决策和调用间隔；32 次请求的端到端耗时合计约 28.51 秒。用例总时间不能当作纯设备执行耗时。

## 本次耗时

以下为 Mac 端 `hostMs`，仅对应这台手机和本轮小样本。

| 操作 | 样本数 | 范围 | 中位数 |
| --- | --- | --- | --- |
| 层级快照＋截图 | 15 | 230–315 毫秒 | 285 毫秒 |
| 点击（含元素或坐标定位） | 8 | 0.40–1.27 秒 | 1.16 秒 |
| 输入 `AgentSoma live 你好`（含聚焦） | 1 | 3.96 秒 | 3.96 秒 |
| 滑动 | 3 | 1.34–2.77 秒 | 2.66 秒 |
| 目标 App 启动 | 2 | 2.50–3.39 秒 | 2.94 秒 |

另开一个仅做 `ping → shutdown` 的计时会话，从启动 Mac 工具到首次 ping 成功为 **5.93 秒**，期间没有锁屏等待提示。前提是已构建安装、开发服务已就绪、手机已解锁；轮询间隔 250 毫秒，仅一次样本，不能当作首次安装或冷启动基准。该计时会话与上面的两轮操作证据分开存放：[启动计时](evidence/live-20260904T144403Z/startup.json)。

## 实现

- [LiveSessionTests.swift](Tests/LiveSessionTests.swift)：一个异步 XCTest 用例保持指令循环，使用 Apple Network.framework 接收 JSON 行，以 Apple XCTest API 操作界面。
- [live.py](live.py)：Mac 端启动与调用工具，仅使用 Python 标准库；启动器调用已有 `iproxy` 和 `xcodebuild`。
- 原有 [AgentSomaTests.swift](Tests/AgentSomaTests.swift) 四项测试保持独立。未提供会话 token 时，新的持续会话用例会跳过；原有 pymobiledevice3 启动脚本显式排除它。

连接路径：Mac 本机 TCP → iproxy → USB/usbmux → iPhone 本机 TCP → XCTest 指令循环。两端监听地址均限定为 `127.0.0.1:47821`，每次启动生成随机 token；含 token 的会话文件权限为 0600，位于 Git 忽略的证据目录。实验限定为 Fixture 和计算器，最长 15 分钟，支持显式 `shutdown`。

这不是 WebDriver 协议，也未引入 WDA 或 DeviceKit 代码。每条请求使用一条 TCP 连接；持续性指的是同一个 XCTest 用例、Runner 进程和设备端会话，连接关闭不应结束该会话。

## 调用

先按 [构建说明](README.md#复现构建与原生启动) 生成并构建工程。在本目录执行，手机需要保持解锁：

```sh
python3 live.py start --udid "$IOS_UDID"
```

启动器输出 `SESSION_DIRECTORY`，该进程持续运行到测试结束。在另一个终端，将 `SESSION_DIR` 设为该目录，再逐条调用：

```sh
python3 live.py call --session "$SESSION_DIR" <<'JSON'
{"op":"ping"}
JSON

python3 live.py call --session "$SESSION_DIR" <<'JSON'
{"op":"launch","bundleId":"com.somnus.agentsoma.spike.fixture"}
JSON

python3 live.py call --session "$SESSION_DIR" <<'JSON'
{"op":"observe"}
JSON
```

`call` 自动添加请求 ID 和会话 token，不会自动重发操作。返回值包含 `ok`、请求 ID、`sessionId`、`runnerPid`、`sequence`、`runnerMs` 和 `hostMs`。截图与完整 JSON 保存到会话目录，控制台只打印摘要。

| 指令 | 参数与语义 |
| --- | --- |
| `ping` | 查询会话信息，不操作 App。 |
| `launch` | `bundleId`；本实验仅允许 Fixture 或 `com.apple.calculator`，启动后检查前台状态。 |
| `observe` | 取得已知前台 App 的单次 AX 快照，随后截图。 |
| `tap` | `identifier`、可选 `elementType`，或屏幕点坐标 `x`、`y`；元素定位要求唯一且可点击。 |
| `type` | `identifier`、可选 `elementType`、`text`；聚焦指定元素后输入，最长 1024 字符。 |
| `swipe` | `identifier`、可选 `elementType`、`direction`（`up` 或 `down`）。 |
| `shutdown` | 回复后结束测试用例，启动器随后关闭 USB 转发。 |

观察 JSON 含最多 200 个节点，每个节点带本次快照的 index/parent、type、identifier、label、value、enabled、frame，并明确标记 `truncated`。节点序号仅属于当前快照。坐标单位是屏幕点，截图尺寸另行返回；层级与截图分别标记时间，不能声称两者是原子快照。计算器文本保留 U+200E 等原始格式字符，验收时只在比较副本中移除 Unicode Cf 字符。

后续新增的 `elementType` 使用快照中的数值类型，例如 49 为文本框、9 为按钮。当前 `identifier` 参数使用 XCTest 的匹配语义，也会匹配 label；WebView 的 DOM id 未必成为 AX identifier。类型过滤与上述原始 32 条请求分轮验证，细节见扩展报告。

系统权限验证另增加可选 `scope: "systemAlert"`，用于 `observe`、`tap`，并限定当前目标为实验 Fixture。它直接查询 SpringBoard 上唯一的 Alert，快照中的 `bundleId` 是 SpringBoard，`targetBundleId` 是 Fixture；未指定 scope 时仍查询原 App。系统没有 Alert 时返回 `system_alert_count_0`。这不提供任意前台 App 发现能力。

## 验证标准

1. 通过外部指令在同一 Runner 会话完成两轮不同操作，期间不重新编译、启动测试或更换 Runner 进程。
2. 从观察结果取得按钮中心坐标，执行坐标点击，并在下一次观察中确认实际变化。
3. 在 Fixture 验证中英文输入与滑动；在计算器验证跨 App 的计算结果。
4. 发出一条不存在元素的指令，确认收到明确错误，随后仍可执行正常指令。
5. 保留每次请求、结果、截图及端到端耗时；最终显式关闭并核对 XCTest 结果。

`runnerMs` 是设备端处理指令耗时，观察包含快照和 PNG 编码；`hostMs` 还包含连接、传输及 JSON 解码，不含 Mac 文件写入。启动前的人工解锁等待必须与自动启动耗时区分。当前数据仅用于可行性验证，不构成性能或兼容性承诺。

主会话中的 32 次正常 TCP 建连与关闭均未中断 Runner。后续还验证了停止并重建 iproxy 后原会话继续，但物理 USB 断开、锁屏后恢复、并发调用、请求去重、未知前台 App 发现，以及正式的产品快照契约仍未完成。pymobiledevice3 已在解锁前提下通过四项核心用例；动态会话仍使用原生 Xcode 启动作为已验证基线。

技术结论：自有 XCTest Runner 已能提供从 Mac 动态调用的观察与操作原语，具备继续开发外部 agent 接口的依据。尚未引入模型、自然语言规划或 MCP；宿主语言和产品接口仍需另行决定。

## API 依据

- Apple 的 [requiredLocalEndpoint](https://developer.apple.com/documentation/network/nwparameters/requiredlocalendpoint) 用于限定监听地址。
- Apple 的 [环境变量说明](https://developer.apple.com/documentation/xcode/environment-variable-reference) 描述了 `TEST_RUNNER_` 前缀向测试 Runner 传递变量的方式。
- 本机 Xcode 16 的 `XCUIElement.h` 声明了公开的 `snapshotWithError:`、`XCUIElementSnapshot.children` 与标准元素属性；本轮用 Swift 的 `app.snapshot()` 读取。
