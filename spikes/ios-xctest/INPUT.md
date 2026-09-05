# XCTest 文字编辑原语

2026-09-05，在当前 iPhone13,3 / iOS 26.6 上，用 Xcode 16 构建并执行独立的 `test05TextEditingPrimitives`。一次测试通过，无失败或跳过。

验证过程只使用现有 Fixture 和 Apple XCTest 公开 API：

1. 点击原生输入框并输入 `ABCDE`。
2. 两次 leftArrow，把光标从末尾移至 C 后；直接 typeText“北京”，实际值为 `ABC北京DE`。
3. Command-A 后输入 `👩‍💻é replacement`，实际值精确替换为该 Unicode 字符串。
4. 再次 Command-A、Delete，输入 `Final` 后只剩 `Final`。

同时记录了 public `hasFocus`：点击前与已获得键盘焦点后均为 false。不能把这个 UI focus 属性当成本环境中的键盘焦点判断。正式 insert 应保留光标，直接调用有键盘焦点前提的 typeText；不能为了输入而再次点击已聚焦字段。replace 可以点击聚焦后使用全选、Delete 和 typeText，不通过 AX value 长度推算退格次数。

[Apple typeText 说明](https://developer.apple.com/documentation/xcuiautomation/xcuielement/typetext(_:))规定目标或后代需要键盘焦点；[hasFocus 说明](https://developer.apple.com/documentation/xcuiautomation/xcuielementattributes/hasfocus)描述的是 UI focus。方向键与组合键来自公开的 [XCUIElement 键盘接口](https://developer.apple.com/documentation/xcuiautomation/xcuielement)。

本结果验证一组原语；CLI 目标校验、动作三态、输入不自动提交以及 WebView 兼容性需要后续动作集成验收，不由这次固定测试代替。

本地证据（git 忽略）：`evidence/input-primitives-20260905-01.xcresult`、`build/stage4-input-test.log`；设备实验文件名为 input-primitives。固定测试保存层级与截图耗时也计入总时长，不能把其 29.8 秒当成文字输入耗时。
