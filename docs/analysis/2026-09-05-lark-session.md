分析对象：[创建 Lark 群聊并发送问候](thread://01a07107-e698-7102-90b0-f7db0233376f?hostId=local)，2026-09-05，全部时间为北京时间。核对了完整任务记录、本机原始事件日志、保留的 XCTest 日志与基线源码。分析基线和原任务记录的提交均为 `223c6d45688897c5f9fbaebe8ff8bbb8f7731866`；后续修复与复测记录在文末。

**结论：31 分钟是执行链路存在严重性能问题的表现。** 确定的主要耗时是 XCTest 等待动画状态通知超时，不能据此认定 Lark 存在持续动画；超时协议、调用工具方式和一次错误的界面理解进一步扩大了耗时。任务最终创建了默认名称为 Hugh、仅含当前账号的群并发送问候语，但 9 个真正派发的点击/输入动作，在 CLI 端全部以 `unknown` 结束。这种完成方式需要逐步查日志救场，尚不能作为日常可用的执行体验。

**实际时间线**

首轮任务从 18:06:48 到 18:37:57，任务记录的耗时为 1,868.567 秒，即 31 分 8.6 秒。18:40 开始的“整理命令与返回”另耗时 110.248 秒，不计入上述时间。

| 阶段 | 时间 | 墙钟耗时 | 其中等待动画状态通知超时 |
|---|---|---:|---:|
| 初始化、连接、打开 Lark、取得首屏 | 18:06:48–18:08:50 | 2 分 1 秒 | 0 |
| 打开新建菜单和建群页 | 18:08:50–18:14:08 | 5 分 18 秒 | 4 分 0 秒 |
| 误把联系人搜索框当群名称，输入后清空 | 18:14:08–18:27:00 | 12 分 52 秒 | 10 分 1 秒 |
| 创建默认群并取得聊天页 | 18:27:00–18:28:58 | 1 分 58 秒 | 1 分 0 秒 |
| 聚焦输入框、输入、发送、验证、清理 | 18:28:58–18:37:57 | 8 分 59 秒 | 6 分 0 秒 |

各阶段按成功观察完成时间分界，因此包括相邻动作间的规划、查询、诊断和等待；不能把整段时间解释为某一个 API 的耗时。

**1. 底层动作每次先后等待界面空闲，是最大瓶颈。**

[原始 xcodebuild 日志](/private/tmp/agentsoma-501/sb0e204b28008441cb5890bc9ba55807c/xcodebuild.log:41)反复出现 `Wait for com.larksuite.lark to idle`，随后约 60 秒出现 `App animations complete notification not received, will attempt to continue.`。全程有 21 次这样的超时，累计 1,261.11 秒，占总时长 67.49%。

以第一个点击为例，测试相对时间为：

| 事件 | 相对时间 |
|---|---:|
| 调用 Tap | 45.61 秒 |
| 开始动作前空闲等待 | 45.62 秒 |
| 未收到动画状态通知，继续执行 | 105.66 秒 |
| 动作后再次等待空闲 | 106.09 秒 |
| 再次等待超时，动作完成 | 166.14 秒 |

一次普通点击因此约需 120.5 秒。`replace` 在 [Runner 实现](/Users/hui/Somnus/Project/super-indie/AgentSoma/Runner/LiveSessionTests.swift:295)中实际执行 `tap → Command-A → typeText`，每个原语又有前后等待。本次给搜索框输入“问候群”触发 6 次 60 秒等待，单条动作约 362 秒。

日志能证明“XCTest 没有收到动画完成通知”，不能单凭这一点断言 Lark 的业务主线程持续阻塞，也不能证明具体是哪一个动画、控件或系统兼容问题。需要用可重复的单次 tap/type 实验继续区分。

用户随后指出界面没有持续动画，只有约 300ms 系统转场。再次核对原任务保存的详细诊断，得到更具体的证据：[事件记录第 357 行](/Users/hui/.codex/sessions/2026/09/05/rollout-2026-09-05T18-05-38-01a07107-e698-7102-90b0-f7db0233376f.jsonl:357)显示 18:18:29.038 开始请求空闲通知，18:18:29.041 主事件循环状态已经从 NO 变成 YES，但动画状态仍为 NO：

```text
18:18:29.039 Requesting animations idle notification using automation session
18:18:29.041 eventLoopHasIdled NO -> YES
18:18:29.042 isQuiescent: self.eventLoopHasIdled: YES && self.animationsHaveFinished: NO
```

以上摘录省略进程前缀；这段采样证实主循环已经报告空闲，等待条件仍卡在动画状态标志。`animationsHaveFinished: NO` 表示 XCTest 未确认动画结束，不是观察到屏幕仍在动。另一次建群转场后的记录确实收到了 `Animations are not active.` 并令该标志变为 YES，因此也不能认定整条通知链从未工作。

原 agent 将“没有收到完成通知”升级为“Lark 持续动画”，缺乏视觉或动画时间线证据。它额外执行的固定 sleep 是自己的恢复策略；每次约 60 秒的底层等待则由 XCTest 的 tap/type 内部同步触发。第一个点击的 60 秒等待在 `Synthesize event` 之前已经发生，不能用该点击随后产生的 300ms 转场解释。后续排查应聚焦空闲检测及通知处理为何未及时完成，具体实现缺陷或版本兼容原因仍未证实。

**2. RPC 超时早于动作结束，健康检查也排在动作后面。**

三个层次的等待并未形成一致的执行预算：

| 层次 | 当前行为 | 源码 |
|---|---|---|
| CLI → Host | 默认 75 秒响应超时 | [SessionClient.swift](/Users/hui/Somnus/Project/super-indie/AgentSoma/Sources/AgentSomaCore/SessionClient.swift:48) |
| Host → Runner | 普通请求默认 45 秒；ping 为 3 秒 | [XCTestBackend.swift](/Users/hui/Somnus/Project/super-indie/AgentSoma/Sources/AgentSomaCore/XCTestBackend.swift:101) |
| Runner 动作 | 本次普通动作约 120 秒，replace 约 362 秒 | [LiveSessionTests.swift](/Users/hui/Somnus/Project/super-indie/AgentSoma/Runner/LiveSessionTests.swift:285) |

45 秒后，[传输层](/Users/hui/Somnus/Project/super-indie/AgentSoma/Sources/AgentSomaCore/JSONTransport.swift:24)关闭连接并报告超时，设备上的 XCTest 动作仍继续运行。没有动作查询接口可以取回后续的完成结果。`unknown` 是缺少证据时正确的保守结果，但 9 个动作全部进入此路径，说明它已经成为常态。

Host 的 `status`、`observe`、动作使用[同一串行工作队列](/Users/hui/Somnus/Project/super-indie/AgentSoma/Sources/AgentSomaCore/SessionHost.swift:127)；Runner 也在主 actor 上[逐个执行请求](/Users/hui/Somnus/Project/super-indie/AgentSoma/Runner/LiveSessionTests.swift:122)。因此健康检查不能绕过慢动作，3 秒 ping 超时混淆了“仍在执行”与“后端不可用”。本次 14 次 status 中 5 次失败；第一次恢复性 observe 也超时。

实际结果是：9 次设备 act 在 Runner 日志均为 `ok=true`，对应 CLI 全为 `outcome=unknown`。额外的一次 type 在 Host 因 `stale_reference` 拒绝，没有发到设备。不能把这 10 次调用解释为重复点击了 10 次，也不能把超时直接解释为动作没有发生。

**3. 调用 agent 误解字段，且没有在歧义处读图。**

建群页的观察只给出 `[e21] text_field`；inspect 返回的 label、identifier 为空，value 为 null。agent 随即把它称为“群名称输入框”，尝试填入用户未指定的“问候群”。实际 XCTest 目标描述是 `Contacts, departments, or groups I manage`，之后页面明确显示没有匹配联系人。

这段包含聚焦、重复聚焦、全选、输入、清空，共 10 次 60 秒动画等待，累计 600.54 秒；加上外围等待和诊断，占据 12 分 52 秒。这个数字和前述 21 分 1 秒有重叠，不能相加。仅从实际轨迹删掉这个分支，其余部分仍约 18 分 17 秒，底层慢动作依然必须处理。

AgentSoma 的[节点导出](/Users/hui/Somnus/Project/super-indie/AgentSoma/Runner/LiveSessionTests.swift:330)没有 placeholder 属性，文字观察在这里缺少语义线索。不过它已返回截图路径，agent 全程只在最后验证消息时打开过 1 张截图，未在识别不清的建群页读图。后续应先验证是否可从原生属性取得占位提示；无法取得时，应把这类歧义交给截图核对，而不是凭字段位置补全含义。本次旧截图已随 disconnect 删除，无法事后确认该提示在截图上的实际可见性。

还有一个独立调用错误：`tap o3:e21` 后继续 `type o3:e21`，复用了已失效引用。这次被正确拒绝，额外增加一轮 observe 和决策。

**4. 长命令的进程结果被丢掉，恢复过程变成固定 sleep 和查日志。**

原任务经常使用：

```javascript
const r = await tools.exec_command({ /* command, yield_time_ms: 30000 */ });
text(r.output);
```

长命令超过 shell 工具的首次等待窗口后，会返回后台进程句柄；只输出 `r.output` 没有保留或转发 `session_id`、退出状态等信息。外层 `functions.wait(cell_id)` 等的是 JavaScript 包装脚本，不能替代对 shell 进程的 `write_stdin(session_id)` 续读。

第一条 tap 的证据很明确：18:09:29 外层 wait 返回“Script completed”且 output 为空；对应 shell 命令直到 18:09:43 才最终返回超时。接下来 agent 又发 observe/status 并转向文件日志排查。命令后来在任务事件中留下的完整失败记录，不等于当时已通过工具结果交付给模型。

本次累计：

- 70 次 shell 执行，其中有 45 次实际 AgentSoma CLI 调用；一次 shell 同时执行了两条 inspect。
- 14 次 status、23 次初始化之后的日志/源码/时间诊断命令。
- 20 次显式固定 sleep，总计 782 秒，即 13 分 2 秒。
- 96 个带 token 用量记录的模型响应，最终只有 9 个设备动作被派发。

固定 sleep 与 XCTest 等待重叠约 655.3 秒；落在已统计的动画等待之外约 127.1 秒。这 127.1 秒也只表示时间区间的位置，不能全算成已经证明可以删除的空等。其余约 8 分钟混合了初始化、普通执行、模型生成、工具调度、日志解读和授权处理等；现有记录不足以把它全部归因为模型推理慢。

任务记录的模型设置是 `gpt-5.6-terra / max`。用量记录累计 input 8,092,125、cached input 7,913,728、output 21,514 tokens；这是多次调用反复携带历史上下文后的累计数，并非 809 万独立输入或未缓存计费量。模型开销值得优化，但本次数据首先指向设备等待和恢复协议。

**排除和边界**

首次设备发现遇到 CoreDevice 初始化超时，消耗约 15.7 秒；实际 connect 约 15.0 秒；open 约 0.9 秒。10 次成功 observe 单次 0.440–0.629 秒，总计 5.501 秒。没有反复重建 Runner，也没有反复断线重连。因此它们不能解释这次 31 分钟。`--idle-timeout 30m` 是会话空闲回收配置，与这次动作的 60 秒等待不是同一机制。

原任务没有在 unknown 后重放建群或发送消息，并最终核对截图、正常 disconnect，这些处理应保留。问题是执行链路持续制造 unknown，迫使每一步进入恢复过程。

**建议的修复顺序与验收**

| 优先级 | 修改目标 | 验收方式 |
|---|---|---|
| P0 | 让 Runner 的空闲/动画等待有适合交互操作的上限，并保留动作前目标检查及动作后观察 | 在本机 Lark 和持续动画 Fixture 上测 tap/type/replace；先以每动作 ≤5 秒、replace ≤10 秒作为工程目标，不再出现反复 60 秒平台 |
| P0 | 对齐动作与响应预算；执行中状态可查询，健康查询能区分 busy 与失联；保留最终结果供取回 | 人为延迟动作超过旧 45 秒边界，验证动作只执行一次、状态可读、后续完成结果可检索 |
| P1 | 修正调用包装，转发完整工具返回，保留 shell session_id，继续读取到进程退出 | 跑一条超过首次 yield 的无副作用命令，能够取得最终 stdout、退出码；不会转去查询设备状态代替进程续读 |
| P1 | 空字段/歧义字段先读图，取得占位语义；动作后使用新引用；已知焦点和内容条件下减少不必要输入原语 | 在同一建群页正确区分联系人搜索和群名称，不再产生误输、清空及 stale_reference 分支 |
| P1 | 记录同一 command ID 的接收、排队、开始、输入派发、完成与耗时；将关键耗时送到 CLI | 日常问题可由结构化记录解释，无需遍历 xcresult 原始日志；延迟测试能按 ID 对账 |

关于 P0 的实现选择：Appium 的[官方设置说明](https://appium.github.io/appium-xcuitest-driver/latest/reference/settings/#waitforidletimeout)提供了 waitForIdleTimeout 和动画等待控制；其 [WebDriverAgent 实现](https://raw.githubusercontent.com/appium/WebDriverAgent/master/WebDriverAgentLib/Categories/XCUIApplicationProcess%2BFBQuiescence.m)通过 Objective-C runtime 替换内部 quiescence 方法、设置应用状态等待超时。它说明该问题有可研究的控制路径，但这些不是当前 Swift Runner 已具备的参数，不能直接把 Appium capability 加到 CLI 就认为修复。采用类似实现前应在当前 Xcode/iOS 组合验证；单纯把 RPC 从 45 秒改成数分钟只会让客户端等得更久。

原实现的 Runner 已计算 `runnerMs`，但当时的 ActionReply.decode 只返回 result，耗时没有传到 CLI；原日志也只有完成标记，缺少 command ID 和各阶段时间。这是可直接改善诊断成本的具体入口。

现有[验收记录](/Users/hui/Somnus/Project/super-indie/AgentSoma/docs/actions.md:55)主要覆盖受控 Fixture 的功能和执行语义。新增验收应同时覆盖持续动画、超时仍在执行、歧义字段和端到端耗时。建议将这种默认单人建群加一句问候的流程设为 1–3 分钟的后续验收目标；这是目标，尚未修复或实测达到。

用户进一步确认：`act` 输入事件执行后，应由 AgentSoma 比较连续帧 hash，直到稳定才认定动作完成。该决定替代此前“输入返回后由 agent 自行决定何时观察”的建议；输入前后引用检查和业务结果判断仍保留。用户随后以“开始修改”授权实施，当前契约见[接口契约](/Users/hui/Somnus/Project/super-indie/AgentSoma/docs/agent-interface.md)。

**证据和统计口径**

- [原始任务事件](/Users/hui/.codex/sessions/2026/09/05/rollout-2026-09-05T18-05-38-01a07107-e698-7102-90b0-f7db0233376f.jsonl:1)：只统计首轮操作，不把后续整理记录纳入任务耗时。
- [XCTest 执行日志](/private/tmp/agentsoma-501/sb0e204b28008441cb5890bc9ba55807c/xcodebuild.log:18)：以 Start Test 的北京时间对齐相对秒数，将等待开始与动画通知超时逐段配对，共 21 段。
- [统计脚本](/private/tmp/agentsoma-lark-analysis-20260905/analyze.py:1)、[统计结果](/private/tmp/agentsoma-lark-analysis-20260905/metrics.json:1)、[等待区间](/private/tmp/agentsoma-lark-analysis-20260905/intervals.json:1)：只读取已有记录；区间取并集/交集，避免把不同层的等待相加。

**后续实施范围（2026-09-05）**

已实现 XCTest application-state 等待的能力检查和 1 秒上限；每个输入原语结束后恢复原值。`act` 在全部输入结束后，使用全帧归一化像素 SHA-256 检测稳定：约 200ms 采样，至少 3 帧一致且跨越 400ms，5 秒检测预算。返回输入事实、稳定状态、最后一帧路径和 `runnerMs`；超时保留事实、使旧引用失效，不重放。Runner 日志现在含设备 command ID 和耗时；CLI 与设备 ID 尚未统一，也没有新增完整排队阶段追踪。

Lark 真机的菜单点击、搜索输入和清空已成功返回 completed，具体测量及最终构建复测见[动作验收](/Users/hui/Somnus/Project/super-indie/AgentSoma/docs/actions.md)。原先每笔 60 秒的通知等待在日志中缩短到约 1 秒；这验证了等待控制路径，不证明 Lark 存在持续动画，也没有定位通知缺失的内部根因。未重跑建群或发送消息。

调用工具必须保留后台任务 ID 并续读原命令的规则已补入 README，本次验证按该方式执行。busy 查询、跨传输超时的结果取回和完整链路 command ID 关联仍是后续工作，不能把本次单动作提速当作这些能力已交付。

用户随后授权完整建群和发送复测，已在 20:03:53 通过截图确认成功。5 个设备动作均 completed，共 28.343 秒；connect 至最终 observe 的 13 条命令累计 48.115 秒，实际墙钟耗时 3 分 34.921 秒。连同此前上下文读取和记录器准备，首次工具调用至读图确认约 5 分 35 秒。设备长等待已消除，但命令间另有 166.805 秒的模型/工具/审批等开销，尚未达到完整流程 1–3 分钟目标。详情见[完整复测记录](/Users/hui/Somnus/Project/super-indie/AgentSoma/docs/actions.md#lark-建群与发送完整复测)。
