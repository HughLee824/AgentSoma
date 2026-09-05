# 设备动作与引用校验

当前提供按引用或明确坐标的画面校验点击/滑动，以及按输入框引用的光标插入、整段替换和独立 Return；文本可从参数或 stdin 读取。用户或调用 agent 负责选择动作并观察结果；AgentSoma 不解释自然语言任务。

## CLI 形式

下面的会话和引用需要替换为实际返回值，每次派发动作后重新 observe。

```sh
agentsoma --session "$SESSION" tap o4:e10
agentsoma --session "$SESSION" swipe o5:e18 --direction up
agentsoma --session "$SESSION" type o6:e8 --mode insert --text '北京'
agentsoma --session "$SESSION" type o7:e8 --mode replace --text '完整的新内容'
agentsoma --session "$SESSION" type o8:e8 --mode replace --text ''
agentsoma --session "$SESSION" type o9:e8 --mode replace --stdin < text.txt
agentsoma --session "$SESSION" press o10:e8 --key return
agentsoma --session "$SESSION" tap o11 --x 100 --y 200
agentsoma --session "$SESSION" swipe o12 --from-x 100 --from-y 420 --to-x 100 --to-y 380
agentsoma --session "$SESSION" tap o13:e10 --protect o13:e20
```

- tap 元素用完整 `oN:eN`。点坐标形式用 `oN --x --y`，单位为屏幕点；不是 PNG 像素，不能同时指定元素引用。点击范围限制在当前已确认的 App 或弹窗内。
- swipe 的 up/down/left/right 描述手指移动方向；宿主根据可见 frame 的 20%/80% 位置生成端点。明确端点形式可控制手指移动距离，速度由 XCTest 的坐标拖动原语决定。tap/swipe 先校验画面再执行坐标，不依赖 identifier/label 唯一性；阈值、附加保护区域、限制见 [动作前画面校验](screen-guard.md)。
- insert 直接向指定输入框发送文字，保留已有光标位置，不额外点击字段。它需要现有键盘焦点；需要聚焦时由 agent 先 tap、再 observe。公开 hasFocus 在本设备中不反映键盘焦点，不能据此预检。
- replace 聚焦输入框后发送 Command-A，非空文本直接覆盖选区；空文本通过 `typeText(XCUIKeyboardKey.delete.rawValue)` 删除选区。没有按 AX value 长度连续退格，也没有自动 Return 或点击提交。
- 文本上限仍是 4096 UTF-8 字节，拒绝换行及控制键；insert 不接受空字符串，replace 空字符串表示清空。
- `--text` 与 `--stdin` 必须且只能选一个。stdin 读取到 EOF，严格解码 UTF-8，不裁剪首尾空格、不去掉末尾换行、不解释转义或执行文本。可用文件重定向或管道；管道生产者需关闭输出。读取到第 4097 字节就拒绝，不为超长输入继续等待 EOF。`--mode replace --stdin < /dev/null` 表示清空。
- `press oN:eN --key return` 向当前输入框发送独立 Return，要求已有键盘焦点，不额外 tap。需要聚焦时先 tap、再 observe。当前只接受小写 `return`，未提供其他按键或组合键接口。具体界面效果由 App 决定，可能提交、换行或无业务变化；调用方仍需 observe 核对。

## 宿主与 Runner 的职责

宿主解析参数、验证会话与当前引用。tap/swipe 从原快照构造坐标与分区截图指纹；type/press 构造目标路径，包含来源节点和祖先的类型、identifier、label、value、enabled、frame，以及每层在父节点内的位置。不向 Runner 发送面向 agent 的观察 ID 或短引用。

这些检查与动作在同一个宿主串行队列执行。两个并发 CLI 命令即使使用同一份当前引用，第一个动作完成后，第二个在解析目标时仍会因引用失效而被拒绝。

薄 Runner 在发送输入前检查：

1. 对应的目标 App 身份与前台状态；SpringBoard Alert 和 App 内 Alert 的存在与数量必须符合观察时的范围。
2. tap/swipe 检查屏幕/范围/方向/键盘上下文，并重新截图。整屏和各保护区域变化在阈值内才执行坐标；不做 AX 目标路径重采样或名称查找。近似通过不保证业务状态未改变。
3. type/press 仍检查当前 AX 中的目标路径和每层属性；frame 允许最多 0.5 点的浮点变化。随后按 type、identifier、label 精确匹配且要求唯一，不通过选择第一个来消除歧义。
4. type/press 目标仍须启用且 isHittable，并为 text field、secure text field、text view 或 search field。坐标动作不保留这项 live 目标语义保证。

App 内唯一 Alert 现在单独作为 `scope=appAlert` 采集，SpringBoard Alert 使用 `scope=systemAlert`。原来没有弹窗的观察不会被用于点击后来出现的弹窗。

Runner 没有跨请求观察缓存、短引用、续期计时或任务策略。它处理当前请求的验证与 XCTest 调用，并在全部输入步骤结束后采帧判断稳定。它不等待业务状态成功；截图与 AX 的非原子采集限制继续成立。

## 执行结果

进入会话的动作结果均为单行 JSON，并保留请求 ID 和 session。stdin 的读取、编码或字节上限错误在 CLI 创建请求前返回 `ok=false`、`outcome=not_dispatched` 和 error，此时没有会话请求关联字段。文本源选择等语法错误继续由 ArgumentParser 输出到 stderr 并非零退出。

```json
{"id":"example-request","session":"example-session","ok":true,"outcome":"completed","result":{"kind":"tap","execution":{"started":true,"inputCompleted":true,"completed":true},"screenGuard":{"algorithm":"srgb-grid-v1","accepted":true,"screenChange":0,"regionChanges":[0],"maxScreenChange":0.01,"maxRegionChange":0,"pixelTolerance":8},"stability":{"stable":true,"samples":4,"consecutiveFrames":4,"stableForMs":563,"elapsedMs":750,"hash":"example-sha256","algorithm":"sha256-rgba8-srgb","sampleIntervalMs":200,"requiredStableMs":400,"timeoutMs":5000},"frame":{"screenshot":"/private/tmp/agentsoma-501/example-session/observations/action/screen.png","hash":"example-sha256","capturedAt":1788608247.676,"width":1170,"height":2532},"runnerMs":3634}}
```

| outcome | 判定 | 引用处理 |
| --- | --- | --- |
| completed | 本动作全部输入调用正常返回，且动作后全帧 hash 达到稳定；不等于业务目标达成 | 旧引用失效，agent 再 observe |
| not_dispatched | 参数、引用或设备目标校验在任何输入 API 调用前拒绝 | 无其他失效原因时保留；若已发现目标或上下文变化则失效 |
| unknown | 输入后未达到帧稳定、已进入输入 API 后出错、执行事实缺失/矛盾，或丢失响应 | 旧引用失效；不重发，agent 先 observe |

每次调用可能发送输入的 API 前，Runner 标记 `execution.started`；任一步骤记录 XCTest 错误就停止，不再继续聚焦后的选区/删除/输入等剩余步骤。全部输入调用正常结束时标记 `execution.inputCompleted`，之后才开始检测帧稳定。App 打开继续使用启动/激活的 started/completed 事实，不纳入 act 的帧检测。

采帧间隔约 200ms，至少 3 帧精确 hash 相同且采样时间跨度至少 400ms 才报告完成；变化会重置稳定窗口，不要求画面先发生变化。图像经方向归一化后，以全尺寸 sRGB RGBA8 像素和尺寸计算 SHA-256，忽略 PNG 编码元数据。哈希计算耗时计入 5 秒预算，但不计入两次采帧之间的稳定跨度。没有区域遮罩或感知相似容差。

5 秒预算到期时返回 `unknown` 和 `frame_stability_timeout`，同时保留 `result.execution.inputCompleted=true`、`result.stability.stable=false` 与最后一帧。该结果确认输入已经完成，只是未获得稳定画面；不能把它解释为没有点击或允许重发。截图/解码失败同样保留可取得的事实；连接丢失且无响应时无法承诺最后一帧可用。预算在截图和处理之间检查，无法中断正在阻塞的 XCTest 截图 API，因此它不是整个 act 的硬超时。

结果只返回最终一张 PNG 的路径和采集时间，不向 agent 输出逐帧图片或 base64。宿主核对图片 hash 与稳定证据后，保存在 `observations/action/screen.png`；下一次带帧的动作覆盖它，disconnect/空闲回收时删除。需要保留时由调用 agent 复制。动作帧不创建观察 ID，不附带旧 AX；后续按引用操作仍需 observe。

Runner 在每个输入原语调用期间，将 XCTest application-state 等待上限设为 1 秒并在结束后恢复原值。这通过运行时能力检查后的 `_XCTApplicationStateTimeout` / `_XCTSetApplicationStateTimeout` 符号实现，没有引入 WDA。连接时能力缺失返回 `unsupported_xctest_runtime`；该内部 API 的兼容性仅在本次工具链/设备上验证，1 秒也不是整个动作的耗时上限。

XCTest 的命令错误经 Runner 转成响应；不再把已经返回给调用方的正常运行时错误一并算作 Runner 整个持续会话的 XCTest 失败。会话外的测试断言和异常结束仍由 XCTest 记录。

无焦点的 typeText 本轮确实发生了 XCTest 内部重试，最终没有写入文字。AgentSoma 的宿主与 Runner 不重新调用结果未知的动作，但单次调用不构成 Apple 内部严格只发送一次底层事件的保证。请求 ID 同样不是去重承诺。

## 验证边界

原始输入探针和修正经过见 [输入原语记录](../spikes/ios-xctest/INPUT.md)。最初“全选、Delete、再输入”的探针没有单独断言清空，非空输入覆盖选区掩盖了 `typeKey(.delete)` 在本设备上不删除选区的问题。现已改为文本删除字符，并在固定测试中加入删除后的即时断言。

当前使用 build-runner 构建并签名的 Runner。画面校验坐标动作使用 `actionVersion=4`、`observationVersion=2`、`screenGuardVersion=1`，保持 `frameStabilityVersion=1`；旧产物连接时返回 `runner_needs_rebuild`，需重新 build-runner 并将新路径用于 connect。第 5 阶段已实现设备/App 发现并移除 open 的 Fixture/Calculator 范围限制，补充了 Settings 导航点击证据，见 [完整调用验收](discovery.md)。下方保留此前 AX 定位和帧稳定阶段的原始验收统计，不代表新增坐标校验已完成相同的真机验收。新契约与证据边界见 [画面校验文档](screen-guard.md)。执行前检查不构成与 App 自行变化原子隔离的事务。

## 验收结果

2026-09-05，macOS 15.0.1 / Xcode 16.0 / iPhone13,3、iOS 26.6：

- `swift test`：24 项通过、0 失败。覆盖既有观察/生命周期、动作参数、来源路径、缺失或矛盾的执行事实、拒绝与 unknown 的引用处理，以及排队动作不能重复使用同一引用。
- 完整真机流程：39 次独立 CLI 调用（包含 connect/disconnect）、17 次观察，始终复用 Runner PID 8853 / UUID `9ED8E711-7EF5-41D2-AE32-2C64E94720C7`。持续会话 XCTest 为 1 通过、0 失败、0 跳过。
- 无焦点 insert 返回 unknown，没有隐式点击或写入；重新观察后继续。Fixture 独立将光标放在 `ABCDE` 的 B 后，CLI 插入 `北京` 得到 `AB北京CDE`；Unicode 整段替换、空字符串清空均通过，提交计数始终为 0。截图核对了插入与清空结果。
- 引用点击使计数增加一次，重复使用旧引用被宿主拒绝；向上滑动改变列表位置。Fixture 自行将目标标签从 Mutable A 改为 Mutable B 后，旧引用在设备校验时被拒绝，计数未增加。
- App 原生 Alert 返回独立范围，同名同标识的重复 Confirm 按钮被拒绝；同一观察下明确坐标点击成功，后续状态为 Confirmed。受控 WKWebView 替换为 `Web 北京🙂`，字段值、页面 JavaScript 回显和截图一致。没有再次请求系统权限。
- 修正后的独立输入原语测试补跑通过（1/0/0），包含删除选区后立即为空的断言。
- disconnect 收到 shutdown 确认，xcodebuild 正常退出，socket 和观察缓存删除；宿主、xcodebuild 及设备 Runner 均确认退出。

测试 Fixture 增加了光标位置、提交计数和延迟改名控件，均只用于验收。首次 CLI 尝试发现激活已安装的旧 Fixture 不会更新这些控件，因此显式安装了本轮构建；产品 open 仍只按运行状态激活或启动。第二次尝试暴露清空问题，修正后第三次完整流程通过。前两次的部分结果不计为完整验收成功。

完整本地证据（git 忽略）为 `spikes/ios-xctest/evidence/actions-cli-20260905-03/`：commands.json、o1–o17 的文本/截图/原始节点、verification.json（断言、清理、源码 SHA256）、swift-tests.log、两份 XCTest 摘要及 run.xcresult。修正后的固定测试结果另存于 `input-primitives-20260905-02.xcresult`。这些文件是开发验收证据，不构成产品任务历史功能。

## stdin 与 Return 补充验收

2026-09-05，代码提交 `3c18f95`，沿用上述 Mac/Xcode/iPhone 环境及已安装 Fixture，构建并安装新版独立 Runner：

- 38 项 Swift 测试通过，包括严格 UTF-8、空白/空文本、4096 字节边界、超过上限但未 EOF 的管道，以及 Return 的引用、目标类型和 unknown 不重发检查。9 项独立 CLI 检查覆盖文本源互斥、缺失文本源、编码/长度错误、空输入和帮助输出。
- 20 次真机 CLI 调用、6 次观察，复用 Runner PID 8946 / UUID `A41EFA9A-2F60-4D30-B4F6-0387E23AD912`。六张 PNG 均实际读取，AX 来源均完整。文件重定向替换保留中文、emoji、组合字符、首尾空格及字面量符号；管道输入在已有光标末尾追加 `尾`，原文逐字节核对通过。
- 带末尾换行的替换、空 insert、未支持的 `enter` 键、非输入框目标和 Return 后复用旧引用共 5 次预期拒绝，均为 not_dispatched。原引用在参数/类型拒绝后仍可用于有效动作；派发后则失效。Runner 日志只有 5 次有效 act，没有收到这些被宿主拒绝的动作。
- 空 stdin 的 replace 在重新输入前立即观察到清空。此前所有输入的提交计数均为 0；通过 `--text` 输入 `Return check` 后，单独 Return 使计数变为 1、键盘收起，字段仍为 `Return check`，旧引用重复调用没有第二次提交。
- 持续会话 XCTest 1 通过、0 失败、0 跳过。disconnect 正常结束，host 6954、xcodebuild 6959 和设备 Runner 均确认退出，socket/观察缓存已删除。

Return 使用 `typeText(XCUIKeyboardKey.return.rawValue)`，其中键常量由 [Apple XCTest API](https://developer.apple.com/documentation/xcuiautomation/xcuikeyboardkey/return) 提供；上面的实际提交效果来自本轮真机证据。此轮仅验证原生 Fixture 的 Return，未扩展到 WebView Return、其他编辑器、更多按键或多行/更长文本。无焦点行为仍受前述 XCTest 内部重试限制约束。

本地证据（git 忽略）在 `spikes/ios-xctest/evidence/input-cli-20260905-01/`，包括 commands.json、六份文本/PNG/节点、stdin 输入文件、local-cli.json、verification.json、源码 SHA256、构建/测试日志及 run.xcresult。Python 记录器仅为开发验收保存 CLI 输出，不属于产品运行链路。

## Lark 等待与帧稳定验收

2026-09-05，同一 Mac/Xcode/iPhone 环境，本次修改后的两个独立签名 Runner 会话共完成 9 个动作，全部返回 `completed`。第一轮验证输入和菜单路径；随后将稳定跨度严格改为采帧时间差、排除 hash 处理延迟，并用最终构建复测空白点击和菜单开关。表中 CLI 耗时从进程开始到退出，Runner 耗时包含目标检查、输入和帧检测；帧检测是其中的一部分，不能相加。

| 场景 | CLI 秒 | Runner 秒 | 帧检测秒 | 采帧数 |
| --- | ---: | ---: | ---: | ---: |
| 打开菜单 | 3.75 | 3.634 | 0.749 | 4 |
| 关闭菜单 | 4.11 | 3.956 | 0.750 | 4 |
| 打开搜索框 | 4.22 | 4.090 | 1.557 | 8 |
| replace 输入 Hugh | 3.87 | 3.728 | 1.169 | 6 |
| replace 清空 | 5.53 | 3.751 | 1.362 | 7 |
| 取消搜索 | 2.70 | 2.556 | 0.747 | 4 |
| 最终构建：空白区域点击 | 3.83 | 3.711 | 0.748 | 4 |
| 最终构建：打开菜单 | 3.78 | 3.646 | 0.753 | 4 |
| 最终构建：关闭菜单 | 3.96 | 3.828 | 0.747 | 4 |

两轮日志中的 14 段动画通知等待均为 1.00–1.02 秒，原任务约 60 秒的平台消失。通知缺失提示仍存在，所以结论是已限制 XCTest 等待，并非已定位通知缺失的内部原因。搜索输入后的 AX 值为 Hugh，清空后的值为空；最后截图确认返回原会话列表，未创建群或发送消息。

`swift test` 最终 47 项通过、0 失败。新增覆盖 PNG 元数据无关性、单像素/尺寸变化、至少三帧与时间窗口的双重条件、变化重置、无变化可完成、处理耗时不得充当稳定时间、超过检测预算不得成功，以及 unknown 保留输入事实/最后一帧、旧引用不能导致再次派发。持续变化超时由确定性本地测试覆盖，本轮未在真机制造持续动画或截图 API 阻塞；不能据此承诺所有 App 都能在 5 秒内稳定。

两个持续会话的 XCTest 均正常通过，disconnect 收到 shutdown 确认、xcodebuild 退出码 0、未强制终止；`ipc.sock` 和观察目录均删除。最终 Runner 构建目录为 `.build/runner/8ada7cc1-d447-46e9-a764-b6a528ea37ac/`。本地证据（git 忽略）在 `spikes/ios-xctest/evidence/frame-stability-20260905-01/`：逐动作 JSON/PNG/CLI 耗时、输入前后 AX、两份 Runner 日志、Swift 测试日志和含源码 SHA-256 的 verification.json。

## Lark 建群与发送完整复测

2026-09-05，用户明确要求再次创建 Lark 群聊并发送消息。复用上述最终 Runner 构建，创建新的默认群 Hugh（1 member），发送“大家好！这是 AgentSoma 优化后的测试消息。”。截图核对了新群的创建提示、完整消息正文和绿色勾选；发送后输入框为空。群和消息保留在 Lark 中。

| 动作 | CLI 秒 | 帧检测秒 | 采帧数 | 结果 |
| --- | ---: | ---: | ---: | --- |
| 打开新建菜单 | 3.771 | 0.760 | 3 | completed |
| 进入 New Group | 3.730 | 0.736 | 4 | completed |
| Create 创建群 | 4.160 | 1.157 | 6 | completed |
| replace 输入测试消息 | 9.859 | 1.371 | 7 | completed |
| 点击发送 | 6.823 | 3.426 | 17 | completed |

全部 5 个设备动作通过稳定检测，没有 unknown、重放或固定 sleep；每个动作结束后调用 observe 获取新引用。发送时实际采了 17 帧才稳定，这一等待来自帧比较结果，不能从中推断具体是哪种动画。日志中 15 段 XCTest 动画通知超时均为 1.00–1.02 秒，无 60 秒等待。

耗时采用三个口径，避免把设备执行时间当成完整用户等待时间：

- 首次工具记录时间 19:58:18 至实际读图确认 20:03:53：约 **5 分 35 秒**，包含读取历史上下文、准备本地记录器、审批、调用与核对，不含其后的清理和报告整理。
- connect 开始 20:00:12.377 至最后 observe 结束 20:03:47.298：**3 分 34.921 秒**。
- 上述 13 条 CLI 命令累计 **48.115 秒**，其中 connect 15.143 秒、5 个动作共 **28.343 秒**。其余 **166.805 秒**在命令执行区间之外，混合了模型读图/决策、工具调度和自动审批，当前记录没有将这些因素逐一拆分。不能声称完整流程只用了 48 秒，也尚未达到此前提出的完整流程 1–3 分钟目标。

第 14 条命令 disconnect 用时 0.505 秒，shutdown 已确认、XCTest 通过、xcodebuild 正常退出，socket 和观察缓存已删除。本次未修改产品源码，也未重新构建 Runner。原始命令/输出、六份观察、各动作结果帧、XCTest 日志、记录器及 verification.json 均保存在 `spikes/ios-xctest/evidence/lark-e2e-20260905-01/`（git 忽略）。
