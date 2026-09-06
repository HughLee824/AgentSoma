# 一次滑动 25.96 秒的等待定位

2026-09-05，在提交 `fe9b41f3b640bba9a7749098c512071f56ce9cd4` 后，分析已经结束的真机验收会话；续查时通过已配对设备接口读取同一时段的 iPhone 历史统一日志。该历史定位阶段没有重新注入 UI 操作或修改等待策略。2026-09-06 用户批准实施后，已完成下述方案 A 修复与 Fixture 真机验收；始终未操作 Lark、未放宽画面阈值。

## 结论

主要延迟是 XCTest 在事件循环空闲等待超时后，同步收集 Spindump 诊断报告，实耗 **23.179 秒**。不是滑动本身需要 26 秒，也不是 AgentSoma 的动作后帧稳定检测耗时过长。

现有 1 秒 application-state timeout 已生效，但只约束空闲条件等待。超时分支另外创建 `getting spindump` 的同步等待，其独立预算是 **600 秒**。本次报告正常返回，没有等满该预算；不能把 600 秒写成本次实耗。

慢动作的事件循环空闲通知在请求后约 1.725 秒到达，此时诊断收集已经开始。收到通知没有提前结束这次诊断等待。因而把 application-state timeout 从 60 秒降到 1 秒，并不等于整个 XCTest 输入调用只有 1 秒等待上限。

续查修正：这个 1.725 秒主要发生在 App 内部等待空闲观察器触发，而非通知传输。两次滑动的观察器都在 UIKit 的滚动结束相关信号之后不到 1 毫秒触发，明显支持它与滚动收尾有关。不能把手指离开后超过 1 秒仍未满足空闲条件认定为异常，之前“保留 1 秒”的建议缺少依据。

Spindump 的 23 秒也已缩小到设备端：`testmanagerd` 记录其调用诊断提供方到收到回调实耗 23.174257 秒。其中采样窗口约 5 秒，采样结束到报告保存又过了约 18.115 秒；报告完成后的读取和回复只在毫秒量级。

## 时间分解

动作：`swipe o4 --from-x 195 --from-y 650 --to-x 195 --to-y 520`；Runner command ID `F1D32275-8F83-4AAC-BDE4-8072494FC70B`，sequence 12。API 是 `press(forDuration: 0, thenDragTo:)`，日志速度为 500 pixels/second。

以下为北京时间；XCTest 活动时间精度为毫秒。父活动包含子活动，不能重复相加。

| 范围 | 起止或来源 | 耗时 |
| --- | --- | ---: |
| 整个 Runner act | 回执 `runnerMs` | 25.956 秒 |
| XCTest 拖动 API，包含以下输入和等待 | 22:08:11.372–22:08:36.187 | 24.815 秒 |
| 其中：合成并发送滑动事件 | 22:08:11.436–22:08:11.989 | 0.553 秒 |
| 其中：动作后 idle 活动，包含超时诊断 | 22:08:11.990–22:08:36.186 | 24.196 秒 |
| idle 内部：实际空闲条件 waiter | 详细日志 `completed after 1.004s` | 1.004 秒 |
| idle 内部：等待 Spindump | 详细日志 `completed after 23.179s` | 23.179 秒 |
| AgentSoma 动作后帧稳定检测 | 回执 `stability.elapsedMs`，4 帧一致 | 0.749 秒 |
| API 和帧检测之外的检查、封装等 | 总耗时扣除二者的差额，非独立采样 | 约 0.392 秒 |

同一会话的另一次向下滑动，Runner 总耗时 2.731 秒，拖动 API 1.585 秒，事件合成 0.816 秒，动作后 idle 活动 0.701 秒，帧稳定检测 0.743 秒。该次空闲通知及时到达，没有产生 Spindump 附件。这是对照证据，不足以保证所有同类滑动都能在 3 秒内完成。

## 三组相互印证的证据

1. `.xcresult` 的活动树：慢动作的最后一个 idle 子活动在 22:08:13.002 开始“App event loop idle notification not received”，至 22:08:36.182 才结束，包含一份 2,374,741 字节的 Spindump 附件。
2. Runner 详细会话日志直接记录：

   ```text
   22:08:11.992 Requesting main run loop idle notification using automation session
   22:08:11.993 Animations are not active.
   22:08:12.999 Wait ... completed after 1.004s
   22:08:13.002 ... failed to quiesce within 1s
   22:08:13.002 Creating future for 'getting spindump' with timeout 600.00
   22:08:13.003 ... entering wait loop for 600.00s ... getting spindump
   22:08:13.717 Got event loop idle reply ...
   22:08:13.718 Event loop is idle.
   22:08:36.182 Wait ... completed after 23.179s
   22:08:36.182 Spindump succeeded with size 2374741
   22:08:36.188 Overriding application state timeout, 1.0 -> 60.0
   ```

   以上摘录省略进程、对象地址和 Fixture 名称。最后一行也确认旧超时是在拖动 API 返回后才恢复，不能把这次长等待归因于提前恢复了 60 秒设置。

3. Spindump 采样自身：22:08:13.061–22:08:18.057，共 500 次、5 秒。Runner 主线程的全部 500 次样本都位于 `LiveSessionTests.performGesture → event → XCTestStateTimeout.perform → XCUICoordinate press → waitForQuiescence → spindumpAttachmentForProcessID:error: → XCTFuture value → XCTWaiter` 同步等待链。Fixture 主线程 495/500 次样本在 Mach 消息等待中，不能据此声称 App 在整个 26 秒内卡死或持续执行动画。

## 续查一：空闲观察器与滚动结束的关系

以下均取自同一份设备统一日志，避免用跨日志时间差计算内部等待：

| 事件 | 慢滑动 | 对照滑动 |
| --- | --- | --- |
| Fixture 安装 idle 观察器完成 | 22:08:11.986456 | 22:10:54.547077 |
| UIKit 处理 `endScrollingWithRegion` | 22:08:13.710052 | 22:10:55.241900 |
| Fixture 的 idle 观察器触发 | 22:08:13.711000 | 22:10:55.242570 |
| 观察器从安装到触发 | 1.724544 秒 | 0.695493 秒 |
| 滚动结束相关信号到观察器触发 | 0.948 毫秒 | 0.670 毫秒 |

两次都在安装观察器后很快回复 `Sending animations idle reply with error: (null)`，但主运行循环的 idle 要稍后才回复。因此，“动画空闲”和“主运行循环空闲”是不同条件，前者不能代替 ScrollView 的真实滚动状态。

`endScrollingWithRegion` 来自 UIKit 的 `UIPointerArbiter` 日志，原文是因为 pointer state / scrollingRegion 不匹配而忽略指针处理。这不能解释成滑动失败：它证明 UIKit 正在处理一个滚动结束相关信号，但不是直接采集的 `isDecelerating = false` 或 delegate 回调。两组小于 1 毫秒的对应关系是支持滚动收尾解释的实测证据，尚非所有内部因果步骤的证明。

慢动作中，观察器触发后 22 微秒便记录 `Sending main run loop idle reply`；Runner 会话日志于 22:08:13.717 收到。跨日志时钟未独立校准，不能把表观约 6 毫秒当作精确 IPC 延迟；但 1.724544 秒已经由同一设备日志定位到 App 内部观察器等待，而不是消息送出后的传输。

本机 Xcode 16 的 `XCTAutomationSupport` 反汇编提供一个实现线索：`XCTMainRunLoopIdleNotifier._queue_setUpRunLoopObserver` 创建一次性 `kCFRunLoopBeforeWaiting`（0x20）观察器，并仅加入 `kCFRunLoopDefaultMode`。所以该版本所指的“空闲”是指定运行循环模式下的一个阶段，不是简单地测主线程 CPU 占用，也不是通用的“所有动画停止”。Apple 的 [Run Loops 文档](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/RunLoopManagement/RunLoopManagement.html)明确说明观察器只有在关联模式下才会收到通知。

但这个静态证据有版本边界：本机 arm64 UUID 为 `9D9CAF93-5199-303E-A92A-2FA997873810`，设备实际发出日志的镜像 UUID 为 `31A7C59D-AFC1-3185-B53D-246639A4146C`。尚未验证设备版本的相同函数，不能据此断言本次惯性滚动全过程运行在 tracking mode。

Apple 的 [UIScrollView.isDecelerating](https://developer.apple.com/documentation/uikit/uiscrollview/isdecelerating)也明确区分手指已离开但内容仍在滚动的状态。因此，用户指出 1 秒对滑动可能过严是合理的；不能因为超过当前预算就反推 App 卡死。

## 续查二：Spindump 的 23 秒在设备端做什么

Spindump 是供排障用的线程调用栈采样报告。这里是 XCTest 因未在 1 秒内取得 idle 确认，进入自动诊断分支；不是执行滑动所必需的步骤。所谓“同步收集”指 Runner 的输入 API 要等待报告返回，即使其间已经收到 idle，也没有取消这次诊断等待。

设备日志与报告的时间对应如下：

| 时间 | 记录 |
| --- | --- |
| 22:08:12.998358 | `testmanagerd` 调用 Spindump，要求采样 5000ms、间隔 10000µs |
| 22:08:13.061–22:08:18.057 | 报告记录的约 5 秒采样窗口，共 500 次 |
| 22:08:18.730604 | `testmanagerd` 发现对应报告文件仍为空 |
| 22:08:18.73–22:08:19.87 | `spindump` 查询应用扩展信息，出现找不到扩展记录的日志 |
| 22:08:21.302076 | 加载缓存：6309 项 CacheData、78 项 CacheExtra |
| 22:08:22.497256 | 连接 `coresymbolicationd` 符号解析服务 |
| 22:08:25.191603–22:08:25.205474 | 找不到匹配的内核，无法建立 kext 符号信息 |
| 22:08:31.361683 | `Unable to inspect [0]: -1` |
| 22:08:36.172035 | `spindump` 记录报告已保存 |
| 22:08:36.172287 | `testmanagerd` 回调：实耗 `23.174257s` |
| 22:08:36.174020 | `testmanagerd` 报告成功，2,374,741 字节 |

所以可以排除“报告已经生成，但大部分时间卡在返回 Runner / USB 传输上”的解释。约 18.115 秒的采样后耗时仍在手机端诊断报告处理链中，其中可见元数据查询、缓存加载和符号解析等工作。日志不是完整 profiler，不能将这 18.115 秒全部分配给符号化，也不能仅凭错误消息断言某个查找失败独占了这些时间。

报告本身包含 409 个进程段，不只是 Fixture。采样的 5 秒内，`spindump` 进程累计 CPU 时间 5.777 秒，其中 `com.apple.spindump.stackshot_parsing` 线程为 4.859 秒，栈上是 `SASampleStore` 解析 stackshot / task container。这说明诊断开销确实不轻；CPU 时间是多线程累计值，不能再与墙钟时间相加。

## 尚未证实与后续验证边界

- 历史两次滑动没有直接采样 `isDecelerating`、`contentOffset` 和实际 run-loop mode，也没有视频；后续新增 Fixture 采样已覆盖这些状态，见实施结果，但不能倒推出历史两次每一毫秒的状态。
- Spindump 在滚动末段已开始采样，诊断负载可能反过来影响滚动耗时。要确定不受诊断干扰的正常等待预算，需要无自动诊断的对照采样，不能只用本次 1.724 秒推定通用阈值。
- 剩余约 18 秒的逐阶段 CPU、磁盘 I/O 或内部阻塞时间，现有历史日志无法精确分摊；完整归因需要采样报告后处理期间的 `spindump` 调用栈。
- 该历史诊断轮没有实施修复；后续是在用户明确批准计划后才进行生产修改与验收。

## 解决计划（2026-09-06 已获准实施）

### 目标、取舍与边界

目标是消除“正常滚动超过短 idle 预算，触发二十多秒同步诊断”的放大效应，同时保证返回成功时有输入完成和画面稳定证据。2026-09-06 用户明确要求“开始按你的计划实施”；以下关卡仍必须实际验证，不能将获准实施等同于方案已有效。

推荐顺序：先验证能否去掉动作路径中的同步 Spindump，再用不受诊断负载干扰的数据选择滑动等待方式，最后做安全回归。推荐取舍是常规输入保留 XCTest 错误、分段计时、截图与执行事实，但不自动生成重型 Spindump；代价是失去这一范围内自动附带的调用栈报告，需要按需另行采集。

不改变画面 guard 阈值、坐标协议、输入事实和 unknown 不重放规则。不将宿主 45 秒 RPC 超时增加作为修复，不新增后台自动诊断服务，不修改 Lark，不升级工具链或引入 WDA。不把“手机原始采样、Mac 后处理”的新架构作为本次修复前提；Spindump 后处理约 18 秒的逐函数归因也不阻塞本次修复。

### 第一步：建立最小可测探针，验证实际设备上的诊断开关

1. 在 Fixture 的受控测试区域记录单调时间、拖动/减速状态、contentOffset、滚动停止时刻；记录 run-loop mode 作为解释线索。只在测试区间有限采样，不替换 SwiftUI ScrollView 的 delegate 或改变滚动参数。
2. 对齐 Runner 的 guard 完成、手势 API 进入/退出、帧稳定完成和回复时刻；手指抬起、idle 请求/回复与诊断事件使用现有 XCTest/设备日志。不要将 API 返回时间标成手指抬起时间。
3. 首先验证候选 `XCTDisableSpindump`。本机 `-[XCUIDevice spindumpAttachmentForProcessID:error:]` 会通过 `NSUserDefaults.standardUserDefaults.boolForKey:` 读取该键，但它是内部 defaults 键，不是公共 API 或已确认的环境变量。设备实际 `XCUIAutomation` UUID 为 `331AECBB-58B3-380F-845D-71AC062F202B`，不同于本机镜像；实验须记录实际加载版本。
4. 在相同 Fixture 起始状态、相同手势/可控非空闲条件下比较“原配置”和“关闭自动诊断”。每组均须实际跨过 idle 预算，不能用未触发超时的快滑动冒充开关验证。先做有界单次对照，确认有效后再重复；不为采集基线反复生成大量重型报告。

验收门槛：开启候选后，日志确认 idle 已超时，却不进入同步 `getting spindump` 等待，也没有对应自动 Spindump 请求/附件；手势只执行一次，XCTest 错误处理没有被整体吞掉。仅能把 defaults 写入再读回，不算开关有效。失败则停止这条生产修改路径，报告不支持的 runtime；不自动扩大到私有方法替换或重写采集系统。

### 第二步：把已验证的诊断控制限制在输入调用范围

在 `Runner/LiveSessionTests.swift` 的 `event` / `XCTestStateTimeout` 附近做局部封装，只有在第一步通过后才实施。保持主线程串行调用，退出作用域时恢复原有超时和诊断配置，包括“原先没有该键”的状态；成功、失败及嵌套作用域都要测试。

优先验证 Runner 进程内的临时覆盖，不通过全局 `defaults write`，不留下持久配置。Foundation 的 argument domain 是非持久的，且查找优先于应用持久域，可作为待验证的实现手段；必须保留其余键及恢复原域，不能覆盖无关启动配置。[Apple defaults 域说明](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/UserDefaults/AboutPreferenceDomains/AboutPreferenceDomains.html)

验收门槛：作用域外配置不变；失败后可继续独立的下一条命令；不重放失败动作；实际 runtime 的受控超时测试通过。尚未测试的工具链组合不宣称受支持，也不在用户 App 中自动制造非空闲状态进行能力探测。

### 第三步：选择滑动等待方案，不直接把全局 1 秒改大

现有 `_XCTSetApplicationStateTimeout` 包住整个手势 API，内部包括动作前和动作后的 idle 等待。guard 在调用 API 前已完成；增大这个值可能拉长 guard 到实际输入的间隔。这是预算修改必须额外验证的风险，而不是已证实发生过误操作。

关闭同步诊断后做两个局部对照：

- A：短 XCTest 等待后交还 Runner，由现有动作后帧稳定检查等待滚动收尾。这里的 1 秒只是试验基线，不被认定为正常滚动必须停止的期限。
- B：仅对 swipe 使用较宽的 XCTest 等待预算，先以 5 秒作为试验候选；它是等待上限，不是每次固定睡眠 5 秒。tap/type 等其他动作不一并扩展预算。

选择规则：A 若能在正常超过 1 秒的滚动中正确完成、没有因 idle 超时产生失败、且最终帧确实稳定，则优先采用改动较少的 A；若 A 不满足，再考虑 B。B 必须证明不会因加长动作前等待而新增过期坐标输入风险；在等待中改变测试页面做对照，不能只测静态页面。若 B 扩大风险，则不直接上线这个全局设置方案，另行规划分离动作前后等待的最小实验。

`FrameStability` 暂不改动：0.2 秒采样、至少 3 帧且连续 0.4 秒一致、5 秒预算。它在手势 API 返回后才开始，不能打断内部 XCTest 同步等待，也不能被称为整个 act 的硬 5 秒上限。先测当前规则是否足够，不引入自适应超时或新的相似度算法。

### 第四步：验收与交付

| 场景 | 必须满足的结果 |
| --- | --- |
| 正常短滑动、超过旧 1 秒的惯性滚动、反向滑动和边界回弹 | 先观察再执行；手势一次；返回成功必须有 guard、输入完成及稳定帧证据 |
| 至少 20 次受控滑动，覆盖列表首/中/尾和两个方向 | 无同步 Spindump 长尾；列出每次分段耗时与最大值，不只报均值。暂定 Fixture 门槛为实际滚动停止后 2 秒内返回，不外推为所有 App 的 SLA |
| 故意跨过选定 idle 预算的条件，至少重复 3 次 | 无同步诊断放大；有错误则如实返回，不把“未采集 Spindump”等同于成功 |
| 输入后画面持续变化、在现有稳定预算内无法稳定 | 不返回 completed=true；若已确定输入完成则保留 inputCompleted=true，否则保持未知；要求重新 observe，不重放 |
| 动作前页面已越过 guard 阈值、前台 App/弹窗范围变化 | 在输入前拒绝，started=false；不能因为性能优化而放宽校验 |
| guard 后内置动作前等待期间页面变化 | 检查是否因预算变更新增使用旧坐标的窗口；出现错误目标输入则该等待方案不通过 |
| XCTest 报错、回复丢失/传输超时、后续下一条命令 | 不伪造输入完成，不自动重试；配置恢复；后续操作必须使用新观察 |
| 既有点击、文本输入、帧稳定、screen guard 和 Host 测试 | 既有测试继续通过，新增诊断配置恢复及滑动等待回归用例 |

超时验收应分开计算动作前等待、手势 API、动作后稳定与传输开销；不能将 5 秒 XCTest 预算解释为总调用最多 5 秒。外层客户端超时不能取消已经发出的设备手势，继续沿用不确定执行结果的处理。

生产变更预期集中于 Runner 的输入等待包装；Fixture 和诊断脚本仅承担受控验证。只有选择的实现确实需要时才提取可测试的小型 helper 或调整宿主能力检查，不为此新增通用策略系统。交付时分别提供最小源码 diff、测试结果、真实设备日志与适用 runtime；回滚按独立修复提交恢复，不依赖清理全局设备设置。

### 实施结果：方案 A 已接入并完成真机验收（2026-09-06）

按 common-ground 的验证关卡，先在实际设备证明开关有效，再接入正式 Runner；没有把仅能读回 defaults 当作能力验证。此前两次初始化超时由设备要求“Enable UI Automation”身份验证导致；用户随后确认已启用，基线与后续实验均正常初始化。没有绕过设备授权或更改配对/开发者设置。

#### 最小生产变更与适用边界

- `Runner/LiveSessionTests.swift:event` 在现有 1 秒 XCTest 输入调用外加 `XCTestDiagnostics.withoutAutomaticSpindump`，作用域结束时恢复原始配置。XCTest 错误检查仍在作用域外正常执行；没有替换私有方法、忽略错误或增加重试。
- 新 helper 仅临时修改 Runner 进程的 argument domain，不写持久域；恢复原值或原先不存在的状态，保留无关键的变化。4 项单元测试覆盖原值、空值、嵌套、抛错和无关配置；argument domain 是进程级，测试间显式还原。
- 为相同设备单调时钟对齐，在原 command 日志追加开始/回复时刻，另记输入 API 进入/退出时刻；不增加公开回执字段或新协议。
- 保持 1 秒 XCTest idle 预算和原帧稳定规则：0.2 秒采样、至少 3 帧且持续 0.4 秒一致、5 秒预算。保持 guard 阈值、输入完成事实及 unknown 不重放语义。方案 A 达标；随后按用户要求额外验证了 3 秒 swipe 候选，结论见下节，生产值没有扩大。
- Fixture 与独立 UI 测试仅用于验收。默认 Fixture 行为不变；`--scroll-wait-probe` 才启用 50ms 有界滚动采样，另加 `--unstable-after-swipe` 才在首次滑动后制造一次 9 秒画面变化，不替换 delegate 或修改滚动参数。

实际验证环境为本机 Xcode 16.0、iPhone 12 Pro / iOS 26.6（23G71），设备加载 `XCUIAutomation` UUID `331AECBB-58B3-380F-845D-71AC062F202B`、`XCTestCore` UUID `EFA99B03-7594-3898-A7C5-8EC0A6D85B9A`。这是内部 defaults 键，不是公开 XCTest API；其他 runtime 组合或未来升级仍须重跑此探针，不宣称通用延迟保证。

#### 真机单次开关对照

同一 Fixture 初始页面、同一 130pt 上滑：

| 指标 | 原配置 | 临时关闭自动 Spindump |
| --- | ---: | ---: |
| 手势 API | 26.215s | 1.663s |
| idle 超过 1 秒 | 是 | 是 |
| 同步 getting spindump | 24.566s，附件 2,571,204 字节 | 无；日志明确记录因键为 YES 不请求 |
| API 返回后的帧稳定检查 | 0.920s | 1.659s |
| 测试结果及配置恢复断言 | 通过 | 通过 |

关闭组附件清单只有自定义 JSON，无 Spindump 附件。Fixture 记录该组首次 `isDecelerating=true` 于 uptime 696374.584778，最后一次为 696376.434813，稳定停止采样为 696376.534814。API 在 696375.793854 已返回，此后帧检查继续等待，而非把 1 秒超时当作动作失败。采样间隔为 50ms，不将这些采样点当作逐帧精确的手指抬起/滚动停止时间。

#### 正式 Runner 的 20 次滑动

每次先 observe，再使用新引用；1–5 从顶部向列表尾部移动，6–10 测尾部回弹，11–15 反向返回顶部，16–20 测顶部回弹。全部成功，均有 guard、`inputCompleted=true`、`completed=true` 和稳定帧证据。

总耗时 2.416–3.620 秒。8 次真实超过 1 秒 idle 预算（第 1–4、11–14 次），8 次均明确跳过 Spindump，满足至少 3 次跨预算验收。连同画面不稳定故障试验，整次正式会话共 9 次 idle 超时、0 次同步 Spindump 请求、0 个 Spindump 附件。按 command ID 去重日志末尾重复的 stdout，不重复计数。

下表单位为秒；“输入前”是 command 开始到输入 API 进入，包含前台/guard 检查，不是纯 idle 等待。“API”仍包含 XCTest 动作前/后等待，不能等同于手指运动时间。“停止后回复”使用 Fixture 和 Runner 的同设备 systemUptime，表示 Runner 发送回复完成相对 50ms 采样所得停止时刻的延迟，不含外部 agent 工具调度耗时。

| 次数 | 手势 | 输入前 | API | 帧稳定 | Runner 总计 | 停止后回复 | idle 超时 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 上滑 130pt | 0.394 | 1.642 | 1.354 | 3.390 | 0.560 | 是（跳过诊断） |
| 2 | 上滑 20pt | 0.410 | 1.447 | 1.356 | 3.213 | 0.522 | 是（跳过诊断） |
| 3 | 上滑 | 0.396 | 1.910 | 1.152 | 3.459 | 0.488 | 是（跳过诊断） |
| 4 | 上滑 | 0.412 | 1.902 | 1.148 | 3.462 | 0.473 | 是（跳过诊断） |
| 5 | 上滑 | 0.392 | 1.639 | 0.749 | 2.780 | 0.691 | 否 |
| 6 | 上滑 | 0.383 | 1.298 | 0.746 | 2.427 | 0.681 | 否 |
| 7 | 上滑 | 0.397 | 1.296 | 0.746 | 2.439 | 0.665 | 否 |
| 8 | 上滑 | 0.385 | 1.282 | 0.749 | 2.416 | 0.660 | 否 |
| 9 | 上滑 | 0.392 | 1.298 | 0.751 | 2.441 | 0.671 | 否 |
| 10 | 上滑 | 0.397 | 1.284 | 0.746 | 2.427 | 0.660 | 否 |
| 11 | 下滑 | 0.394 | 1.892 | 1.151 | 3.438 | 0.490 | 是（跳过诊断） |
| 12 | 下滑 | 0.387 | 1.884 | 1.151 | 3.422 | 0.453 | 是（跳过诊断） |
| 13 | 下滑 | 0.400 | 1.907 | 1.157 | 3.464 | 0.473 | 是（跳过诊断） |
| 14 | 下滑 | 0.561 | 1.903 | 1.155 | 3.620 | 0.498 | 是（跳过诊断） |
| 15 | 下滑 | 0.400 | 1.290 | 0.745 | 2.435 | 0.697 | 否 |
| 16 | 下滑 | 0.406 | 1.305 | 0.747 | 2.458 | 0.685 | 否 |
| 17 | 下滑 | 0.399 | 1.303 | 0.747 | 2.449 | 0.703 | 否 |
| 18 | 下滑 | 0.399 | 1.299 | 0.742 | 2.441 | 0.676 | 否 |
| 19 | 下滑 | 0.550 | 1.302 | 0.749 | 2.601 | 0.665 | 否 |
| 20 | 下滑 | 0.400 | 1.304 | 0.749 | 2.454 | 0.666 | 否 |

停止后回复最大 0.703 秒，低于暂定 Fixture 门槛 2 秒。原始单调时间、终点 offset 和分段数据见 `acceptance-timings.json`；Fixture 采样有 20 组 active/settled，对应 20 次实际输入。没有将总耗时大于 1 秒的动作都计为 idle 超时。

#### 安全与错误回归

- **画面持续变化**：首次滑动触发 9 秒变化标记；正式 Runner 的帧检查采到 25 帧、约 5.043 秒仍不稳定，返回 `frame_stability_timeout`、`outcome=unknown`、`requiresObservation=true`。保留 `started=true,inputCompleted=true,completed=false`；总计 7.488 秒，未谎称整个调用被硬限制为 5 秒。Fixture 仅一组 active/settled，标记按时结束，没有重放。
- **后续独立命令**：重新 observe 后点击 Increment 成功，Count 由 0 变 1；文本框正确写入 `swipe wait fixed`，显式 Return 后 Submissions 由 0 变 1。
- **目标局部变化**：观察 Mutable A 后等待其变为 B，旧目标点击被拦截，`screen_changed`、`not_dispatched`、`started=false,inputCompleted=false`；目标区域变化 0.018229，高于保持不变的 0 阈值，Count 仍为 1。
- **整页变化**：观察后通过测试重启重置 Fixture，旧观察滑动被拦截，`started=false`；全屏变化 0.067383，高于原 0.01 阈值，未注入手势。
- **XCTest 真错误及恢复**：独立 `test03XCTestErrorRestoresConfiguration` 查询一个确定不存在的 Fixture 按钮，取得真实 `Failed to tap ... No matches found` issue，断言错误未消失、超时及 argument domain 完全恢复；随后正常点击 Increment，Count 为 1。该测试通过（6.422 秒）。探针只捕获预期错误区间，恢复断言及后续点击的错误仍正常上报。
- **宿主预检**：此前尝试不存在的 Fixture bundle ID 被 `app_not_installed` 提前拒绝，没有进入 XCTest；这一结果不算 XCTest 错误恢复证据，没有绕过预检。
- **本地回归**：最终 `swift test` 67 项、0 失败（含新增 4 项），约 4.50 秒；其中含帧稳定、context/guard、点击/文本、回复丢失、传输不确定及旧引用不重放用例。context 单测具体覆盖方向、键盘数量和 scope 范围变化；传输故障也使用现有本地测试覆盖。本轮没有在真机额外故障注入前台 App 切换/系统弹窗或强制断开输入传输，不能将这些写成新的真机实测。动作前后等待未分离；既有 guard 到 XCTest 内部输入的间隙仍存在，未声称消除所有 TOCTOU 风险。

#### 补充验证：3 秒 swipe idle 候选被拒绝（2026-09-06）

用户提出“滑动手指离开后仍有惯性滚动是正常的，是否应放宽 1 秒 XCTest idle timeout”。这不是单纯的动作后收尾预算：`_XCTSetApplicationStateTimeout` 覆盖整个 `press(forDuration:thenDragTo:)`，包括 XCTest 在注入坐标前的 quiescence 等待；而 screen guard 已在进入该 API 前完成。因此在把生产值从 1 秒改为 3 秒前，使用 Fixture 做了一次专门的 TOCTOU 对照，期间未操作 Lark。

Fixture 在点击“Arm controlled motion”后启动 8 秒的不可见 1pt UIKit 动画，使 XCTest 保持 `animationsHaveFinished = NO`，并在 5 秒时将原蓝色滑动面切换为红色 tripwire。切换前后两个面使用相同的屏幕坐标；触摸回调把实际的 `touch_began` / `touch_ended` 和当时的 route 写入测试 App 的 Documents。每组均使用相同的命令链：observe original → arm → fresh observe original → swipe；候选组的 guard 已接受 original 后才进入 3 秒 XCTest waiter。

| Runner 的 swipe timeout | guard | 实际 touch_began | 实际 touch_ended | route 切换 | 结论 |
| --- | --- | --- | --- | --- | --- |
| 1 秒（现生产值） | accepted，original | 动画开始后 3.935 秒，original | 4.251 秒，original | 5.248 秒 | 整个手势在切换前约 0.98 秒结束 |
| 3 秒（临时候选） | accepted，original | 动画开始后 6.096 秒，tripwire | 6.396 秒，tripwire | 5.264 秒 | 输入在切换后约 0.83 秒才开始，使用了旧观察的坐标 |

候选 Runner 诊断明确记录 `entering wait loop for 3.00s`，随后 `failed to quiesce within 3s`；其 screen guard 仍为 accepted。因而风险不是 guard 失效，而是 guard 与实际 HID 注入之间多出来的 2 秒窗口。候选 swipe 的 `runnerMs` 为 6.186 秒，基线为 3.742 秒；这也没有带来已需要的性能收益，因为方案 A 已消除了 23 秒 Spindump 长尾。

临时生产改动已在验证后撤回：`Runner/LiveSessionTests.swift` 继续对所有输入使用 1 秒 timeout。保留的 `--preinput-wait-probe` 仅存在于 Fixture 测试 App，用于未来若要重新设计“前置短等候 + 动作后更宽等候”时做回归；默认 Fixture 和生产协议不受影响。若未来确有必要增加动作后等待，正确的下一项工作是将动作前和动作后 XCTest 等待分离，并在输入前重新校验页面，而不是直接扩大现有 API 的统一 timeout。

#### 交付与证据

正式签名 Runner 构建成功，最终使用 `.build/runner/647c3591-585f-4b1d-9acc-33b2427d1248/` 的产物验收。`git diff --check` 通过。正式会话已显式 disconnect，`forced=false`、`shutdownAcknowledged=true`、xcodebuild 退出码 0，观察缓存按现有生命周期清理；独立探针也正常退出。未操作飞书，未提交或推送，未留下持久 defaults 修改。

本轮证据根目录：`spikes/ios-xctest/evidence/swipe-fix-20260906.q4NsSQ/`（Git 忽略，不上传/提交原始设备归档）。

- `baseline-authorized.xcresult`、`disabled.xcresult` 及各自 diagnostics：有效基线/关闭组；此前 `baseline.xcresult`、`baseline-retry.xcresult` 为已解决的授权初始化失败，不计入性能结果。
- `baseline-scroll.json`、`disabled-scroll.json`、`disabled-attachments/manifest.json`：开关门槛和采样依据。
- `acceptance-1-5.json` 至 `acceptance-16-20.json`、`acceptance-scroll.json`、`acceptance-timings.json`：20 次逐条回执、观察文本与分段计时。
- `production-diagnostics/`、`production-diagnostics-summary.json`、`production-attachments/manifest.json`：实际超时/跳过次数和附件清单。完整原结果仍位于 `/tmp/agentsoma-501/s6f3caebae5f74869965c307d4ca6196d/run.xcresult`。
- `preinput-wait/baseline-1s-5s-swap.json`、`preinput-wait/candidate-3s-5s-swap.json`：实际触点 route 的 1 秒/3 秒对照；相邻 diagnostics 目录包含对应 XCTest waiter 日志。`armed-too-early.json` 和早期 `baseline-1s.json` 是定时窗口不充分的试跑，不作为结论依据。
- `unstable-action.json`、`unstable-scroll.json`、`unstable-frame.png`、`text-regression.txt`、`guard-regression.json`、`page-guard.json`：失败事实及恢复回归。
- `error-recovery.xcresult`、`error-recovery-diagnostics/`：真实 XCTest 错误与配置恢复探针；`xctest-error.json` 则是宿主提前拒绝未安装 App 的记录，不能混用。

## 可复核的本地证据

- 原始结果：`/tmp/agentsoma-501/s16cd41ee114e406f8bfa0da4262594f4/run.xcresult`。通过 `xcresulttool get object --legacy` 读取测试 summary 对象 `0~czcDXDJx7kDPS1o2cCn2_LlTWhoiDS1T1puOt7lnFBtKO2LCCO-kbswl1Rr4lbZVV0TqWX7Z0emzKIKkChObwg==`，其中包含活动的 start、finish 和附件引用。
- 原始 CLI 回执：`spikes/ios-xctest/evidence/screen-guard-20260905.Uv9lt0/commands.json`。
- 本轮导出：`spikes/ios-xctest/evidence/swipe-wait-20260905.LSCdyh/`，包含 `activity-metrics.json`、`Spindump.txt` 和 `diagnostics/`。详细日志文件名为 `Session-AgentSomaTests-2026-09-05_220020-0X4nEv.log`，关键段为 4510–4578 行；Spindump 的 Runner 调用链在 727–753 行。这些完整诊断文件仅保留在 Git 忽略目录，不进入源码提交。
- 续查导出：`spikes/ios-xctest/evidence/swipe-followup-20260905.PZ9mFX/`，包含设备历史日志 `iphone-relay.logarchive`、`slow-swipe-system.filtered.ndjson`、`slow-swipe-fixture.ndjson`、`fast-swipe-fixture.ndjson`、`scroll-idle-markers.ndjson` 和派生计算 `followup-metrics.json`。只查询 Fixture、XCTest 和报告生成相关日志；原始设备归档保留在 Git 忽略目录，不上传或提交。
- 静态检查对象：`/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/Library/PrivateFrameworks/XCTAutomationSupport.framework/XCTAutomationSupport`。arm64 的 `0x15dd4` 设置 activity 0x20，`0x15dd8` 设置非重复，`0x15e08` 引用 `kCFRunLoopDefaultMode`，`0x15e14` 调用 `CFRunLoopAddObserver`。这份本机镜像不是设备 runtime，只作实现线索。
- 产品调用位置：`Runner/LiveSessionTests.swift` 的 `XCTestStateTimeout.perform`、`event`、`performGesture`、`waitForStableFrame`。历史定位时未改动；后续修复仅在 `event` 加入局部诊断包装及计时日志，等待预算和 guard 实现保持不变。
