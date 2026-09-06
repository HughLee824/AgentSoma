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
- swipe 的 up/down/left/right 描述手指移动方向；宿主根据可见 frame 的 20%/80% 位置生成端点。明确端点形式可控制手指移动距离，两种形式均支持下述速度和停留参数。tap/swipe 先校验画面再执行坐标，不依赖 identifier/label 唯一性；阈值、附加保护区域、限制见 [动作前画面校验](screen-guard.md)。
- insert 直接向指定输入框发送文字，保留已有光标位置，不额外点击字段。它需要现有键盘焦点；需要聚焦时由 agent 先 tap、再 observe。公开 hasFocus 在本设备中不反映键盘焦点，不能据此预检。
- replace 聚焦输入框后发送 Command-A，非空文本直接覆盖选区；空文本通过 `typeText(XCUIKeyboardKey.delete.rawValue)` 删除选区。没有按 AX value 长度连续退格，也没有自动 Return 或点击提交。
- 文本上限仍是 4096 UTF-8 字节，拒绝换行及控制键；insert 不接受空字符串，replace 空字符串表示清空。
- `--text` 与 `--stdin` 必须且只能选一个。stdin 读取到 EOF，严格解码 UTF-8，不裁剪首尾空格、不去掉末尾换行、不解释转义或执行文本。可用文件重定向或管道；管道生产者需关闭输出。读取到第 4097 字节就拒绝，不为超长输入继续等待 EOF。`--mode replace --stdin < /dev/null` 表示清空。
- `press oN:eN --key return` 向当前输入框发送独立 Return，要求已有键盘焦点，不额外 tap。需要聚焦时先 tap、再 observe。当前只接受小写 `return`，未提供其他按键或组合键接口。具体界面效果由 App 决定，可能提交、换行或无业务变化；调用方仍需 observe 核对。

## 可控拖动

`swipe` 的起终点规定手指轨迹，不承诺内容滚动多少点或选中多少格。以下参数控制拖动过程，默认值保留此前实测的 500 / 0 / 0 行为：

| 参数 | 含义 | 范围 | 默认值 |
| --- | --- | --- | --- |
| `--velocity` | 移动速度，采用 XCTest 的 pixels/s 单位，不将其当作 PNG 坐标 | 大于 0、至多 10000 | 500 |
| `--press-duration` | 开始移动前按住的秒数；可用于先长按再拖动 | 0–5 | 0 |
| `--hold-duration` | 到达终点后、抬手前停留的秒数 | 0–5 | 0 |

例如以下轨迹只能在当前观察确实提供对应滚轮/事件位置时使用，引用和坐标必须替换为实测值：

```sh
# 滚轮微调：降低速度，到达终点后短暂停留，再抬手。
agentsoma --session "$SESSION" swipe o12 \
  --from-x 98 --from-y 385 --to-x 98 --to-y 337 \
  --velocity 100 --hold-duration 0.2
agentsoma --session "$SESSION" observe

# 已重新观察的事件块：先按住，再慢速移动。
agentsoma --session "$SESSION" swipe o13 \
  --from-x 110 --from-y 536 --to-x 110 --to-y 561 \
  --velocity 100 --press-duration 0.5 --hold-duration 0.2
agentsoma --session "$SESSION" observe
```

上述参数是试验起点，尚未证明能让任意 App 的滚轮恰好移动一格。到达目标附近时优先使用明确端点；方向形式移动可见区域的 60%，可能跨多格。先读当前值，执行后再读实际值；无变化或反向过冲时调整速度、结束停留或交互方式，不能只把距离越试越小。原生 `picker_wheel` 与自定义 `scroll_view` 不能混为同一种能力。

宿主和 Runner 均校验参数及动作预算。以 `起始停留 + 路径屏幕点距离 × 截图倍率 / 速度 + 结束停留` 保守估算，超过 10 秒的请求在派发前返回 `swipe_duration_exceeded`，不消耗当前引用；应缩短路径/停留或加快速度。这个预算用于限制请求的运动过程，不是整个命令的硬超时；XCTest 前后等待及帧检测仍使用现有策略。

成功回执增加 `result.motion`，例如 `{"velocity":100,"pressDuration":0.5,"holdDuration":0.2}`。它表示 Runner 调用 XCTest 时采用的参数，不是从触摸硬件采样出的实测速度。宿主核对它与请求一致；缺失或不一致时保留输入事实及可用结果帧，返回 `unknown` / `missing_swipe_motion_facts`，不重放。`completed` 仍只表示输入结束且画面稳定，目标值必须由调用 agent 核验。

本地验证覆盖参数拒绝、默认值兼容、两种目标形式的参数传输、Runner 共享模型解码、包含截图倍率及两端停留的预算、旧 Runner 拒绝、回执不一致以及拒绝后引用仍可用。2026-09-06 的 `swift test` 为 73 项通过、0 失败。非默认时长的 Lark 实机验收由用户另开 session 进行，本轮没有创建测试日程。

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

## 兼容性与验证边界

当前设备协议为 `actionVersion=5`、`observationVersion=2`、`screenGuardVersion=1`、`frameStabilityVersion=1`。发布用户安装配套版本并重新 setup；源码开发者重新 build-runner，并使用新路径 connect。旧 Runner 不会静默忽略速度与停留参数。

本地测试覆盖输入校验、引用失效、执行事实、画面校验和帧稳定；真机兼容性以 [README 中的实测环境](../README.zh-CN.md#前置条件)为限。历史操作记录、截图和诊断日志仅保留在本地，不作为公开运行依赖。执行前检查不构成与 App 自行变化原子隔离的事务。
