# 动作前画面校验与坐标执行

用户在 2026-09-05 确认“按这个方向继续”。本阶段覆盖 tap/swipe：宿主根据原观察准备坐标和画面指纹，Runner 重新截图并校验，通过后执行坐标手势。type/press 的 AX 目标解析、动作后的精确帧稳定检测、每次派发后重新 observe、unknown 不重发均保持不变。

这是启发式的动作前置条件，不是页面 ID、目标身份保证、业务正确性或事务隔离。每次 observe 仍产生新引用；相似画面不延长引用，也不合并观察。

## 调用方式

```sh
agentsoma --session "$SESSION" tap o1:e10
agentsoma --session "$SESSION" tap o2 --x 195 --y 380
agentsoma --session "$SESSION" swipe o3:e50 --direction up
agentsoma --session "$SESSION" swipe o4 --from-x 97 --from-y 405 --to-x 97 --to-y 365
agentsoma --session "$SESSION" tap o5:e10 --protect o5:e20 --protect o5:e21
agentsoma --session "$SESSION" tap o6:e10 --max-screen-change 0.01 --max-region-change 0
```

上面的引用、坐标均为示例，不能直接用于当前设备。`--protect` 可重复最多三次，引用必须属于这次动作的同一观察；适合显式保护要保存的日期、数量、对象名称等。默认不会推断哪些业务字段重要。

- 元素 tap 使用捕获 frame 与当前观察 scope 相交部分的中心点。元素 swipe 使用该区域轴向 80%→20%（up/left）或 20%→80%（down/right）的端点。空 identifier/label 不影响坐标解析。禁止自动滚动寻找离屏元素。
- 坐标 swipe 必须同时提供四个端点参数，以观察 ID 为引用，不能混用元素引用或 `--direction`。单位是屏幕点，不是 PNG 像素；起终点必须在原 scope 内且至少相距 1 点。
- Runner 使用 XCTest 坐标 tap，或 `press(forDuration: 0, thenDragTo:)`。后一项为坐标拖动原语，速度由 XCTest 决定；不会声称是精确时长/速度的底层 HID swipe。
- `--max-screen-change` 和 `--max-region-change` 满足 `0 <= region <= screen <= 1`。修改阈值是调用方明确选择，Runner 不会自动放宽阈值、重试或修正坐标。设置为 1 会使对应相似度限制失去拦截能力，上下文检查仍有效。

## 算法及责任边界

共享的 `ScreenGuard.swift` 是宿主与 Runner 编译使用的无状态比较模块，不拥有 AX 查询、短 ID、缓存或任务策略。

1. 宿主从观察中读取截图、screen/scope frame、设备 orientation、键盘数量，将元素引用解析为坐标，并生成基准指纹。
2. 指纹算法 `srgb-grid-v1` 将截图按图片方向归一化，以固定屏幕坐标裁剪，再采样到 sRGB RGB 网格。整屏为 32×64，保护区域为 48×48；保留颜色，不做平移对齐、旋转容差或语义嵌入。
3. 每个网格单元任意颜色通道的差值大于 8/255 即算变化。变化比例是变化单元数除以总单元数，不是原始像素面积比例，更不是“页面相同的概率”。
4. 自动保护触摸起点周围 64×64 点；swipe 另保护起终点包围框向外扩展 16 点的区域。保护区域裁剪到屏幕，额外 `--protect` 使用引用可见部分。最多五块局部区域，完整命令受已有 60 KB 宿主预算/64 KiB Runner 请求限制约束。
5. Runner 保留前台 App 和 App/System Alert 范围检查；屏幕和 scope 的 frame 最多容忍 0.5 点差异，orientation、键盘数量和截图像素尺寸必须一致。不相符则在输入前拒绝。AX 的完整重采样和 type/identifier/label 查询不再进入 tap/swipe 路径；这些动作的 XCTest 内部行为不在此保证内。
6. Runner 采集一张新截图，与命令携带的原始基准比较。整屏和每一块保护区域都通过各自阈值后，才进入标记 `execution.started` 的输入调用。Runner 不长期保存原始截图或 AX 树。

默认整屏阈值 0.01、局部阈值 0，属于保守工程初值，不是经过多 App 校准的安全值。局部 0 仍允许颜色噪声底限内的变化和降采样无法分辨的变化。

现有归一化像素 SHA-256 保留，用于精确帧身份和动作后稳定证据校验；相似度网格是额外的参考特征，不通过 SHA-256 字符差异衡量画面变化，也不修改动作后的 200ms/3 帧/400ms/5 秒规则。

## 结果与失败

动作结果附带 `result.screenGuard`：algorithm、accepted、screenChange、regionChanges、阈值、区域边界和采集时间。不会把基准 RGB/base64 输出给调用 agent。宿主对成功的坐标动作核对校验分数、阈值与通过事实；缺失或矛盾的成功证据转成 unknown。

- 超阈值：`screen_changed`、`not_dispatched`、`requiresObservation=true`，已知没有发送输入；原引用失效。
- 上下文变化或采样/指纹不可用：同样在输入前拒绝，返回具体 reason 并要求重新 observe；缺失证据不是零变化。
- 参数、坐标、保护引用不合法：宿主或 Runner 拒绝，不发送输入。
- 输入后的失败、丢失响应、画面不稳定：沿用 unknown 和不重发规则，不把动作前的通过证据当成动作完成。

设备协议现在是 observationVersion=2、actionVersion=4、screenGuardVersion=1、frameStabilityVersion=1。旧 Runner 在 connect 时返回 runner_needs_rebuild，必须重新 build-runner，不静默回退到无校验坐标输入。

## 验证边界与剩余风险

本地验证覆盖：完全相同/仅编码元数据不同、小范围无关刷新、小范围目标变化、操作区不变但整屏大变、按钮不变但额外日期区改变、颜色变化、左上角坐标方向、阈值边界与噪声底限、方向/键盘/范围/尺寸变化、缺失指纹、手势保护区域不可省略、空名称滚轮的坐标映射、最大报文预算、失败事实与引用失效、旧协议拒绝。

本地测试数据是固定合成像素和已记录 AX；通过这些测试不证明任意 App 的误放行率或真机性能。还需扩大真实刷新/遮挡/重排样本来校准阈值。后续证据与未验证项应明确区分，不通过调高阈值掩盖失败。

降采样可能遗漏细小文字或局部变化；大区域内的小变化也可能被稀释。不可访问的遮挡、无可见变化的 enabled/focus 更新、相同画面背后的业务状态变化不能仅靠截图保证。坐标 tap 不再承诺旧 AX 路径的 live enabled/isHittable 检查。需要精确命中时使用明确坐标，重要上下文由调用方保护并在动作后检查。

AX 与截图的 observe 采集不是原子的，动作前采样与触摸也不是原子的。此校验不会冻结 App，也不承诺检测所有输入前变化。若后续要为动作后稳定检测加入相似容差，需要独立的固定窗口基准规则，不能把相邻帧小幅变化误判成停止运动。

## 2026-09-05 有界真机验收

环境：macOS 15.0.1 / Xcode 16.0 / iPhone 12 Pro、iOS 26.6，现有 AgentSoma Fixture；没有操作 Lark 内容。独立 Runner 的 iOS 编译及现有开发签名验证通过。本地回归共 63 项，0 失败。

同一 Runner 会话进行了 7 次观察和 6 个动作：5 次 completed、1 次预期的输入前拦截，没有 unknown 或重放。所有阈值保持默认值。

- Increment 由 Count 0 变为 1；带额外 Mutable B 保护区域的点击随后由 Count 1 变为 2，Submissions 始终为 0。
- Fixture 定时将 Mutable A 改为 Mutable B。旧观察的按钮点击返回 screen_changed：screenChange=0.0009765625（约 0.098%，低于整屏 1%），regionChanges=[0.0182291667]（约 1.823%，高于局部 0）。execution.started=false，重新 observe 的 Count 仍为 1，没有触发按钮的 +100 行为。
- 正常动作也出现过非零整屏变化（0.00048828125、0.00146484375），局部变化为 0，仍正常通过。此证据说明阈值确实应用于放行，不将变化原因推断为特定通知或时钟。
- 明确端点 (195,650)→(195,520) 的手势使列表由 0% 滚到 19%；截图确认首个可见行由 Row 0 变为 Row 6。元素引用的向下手势随后回到 0%。手指距离不等于列表内容位移，滚动有惯性。
- 三次成功 tap 的 Runner 总耗时约 1.75–1.90 秒；输入前拒绝约 0.39 秒；两次 swipe 分别约 25.96 秒和 2.73 秒。前者在进入 XCTest 手势之后有长等待，不能据此宣称本次改动已消除 XCTest 输入/截图等待。未单独测量图像比较 CPU 耗时，也不提供 p95 性能保证。
- disconnect 返回 shutdownAcknowledged=true、forced=false、xcodebuildExitCode=0，并清理观察缓存。持续 XCTest 会话 1 通过、0 失败。相关截图已另存，不依赖已清理的会话缓存。

本地证据（Git 忽略）：`spikes/ios-xctest/evidence/screen-guard-20260905.Uv9lt0/`，包含 CLI 回执、o3–o7 的截图/AX、最终动作帧、构建路径、测试与 Runner 日志。未在真实 Lark 日期滚轮上做此版本的操作验收，未新增权限弹窗、屏幕旋转或真机焦点切换测试；这些不应被上述通过结果覆盖。
