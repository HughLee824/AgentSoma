# XCTest 文字编辑原语

2026-09-05，在当前 iPhone13,3 / iOS 26.6 上，用 Xcode 16 构建并执行独立的 `test05TextEditingPrimitives`。首次原语测试通过；后续 CLI 验收发现清空断言缺失，修正后再次运行，一次测试通过，无失败或跳过。

验证过程只使用现有 Fixture 和 Apple XCTest 公开 API：

1. 点击原生输入框并输入 `ABCDE`。
2. 两次 leftArrow，把光标从末尾移至 C 后；直接 typeText“北京”，实际值为 `ABC北京DE`。
3. Command-A 后输入 `👩‍💻é replacement`，实际值精确替换为该 Unicode 字符串。
4. 再次 Command-A、`typeText(XCUIKeyboardKey.delete.rawValue)`，立即断言字段为空或显示 placeholder；再输入 `Final` 后只剩 `Final`。

首次测试第 4 步使用 `typeKey(.delete, modifierFlags: [])`，只断言后续的 `Final`，没有即时核对删除结果。CLI 验收发现此 Delete 调用正常返回却未删除选区；后续非空输入覆盖选区，掩盖了失败。生产路径现为：非空 replace 聚焦、Command-A、直接 typeText 覆盖选区；空 replace 使用文本删除字符。修正后的固定测试和 CLI 清空观察均已通过。

同时记录了 public `hasFocus`：点击前与已获得键盘焦点后均为 false。不能把这个 UI focus 属性当成本环境中的键盘焦点判断。正式 insert 保留光标，直接调用有键盘焦点前提的 typeText；需要聚焦时由 agent 先点击并重新观察。replace 不通过 AX value 长度推算退格次数。

[Apple typeText 说明](https://developer.apple.com/documentation/xcuiautomation/xcuielement/typetext(_:))规定目标或后代需要键盘焦点；[hasFocus 说明](https://developer.apple.com/documentation/xcuiautomation/xcuielementattributes/hasfocus)描述的是 UI focus。方向键与组合键来自公开的 [XCUIElement 键盘接口](https://developer.apple.com/documentation/xcuiautomation/xcuielement)。

本结果验证一组原语；CLI 目标校验、动作三态、输入不自动提交以及受控 WebView 的独立集成证据见 [动作验收](../../docs/actions.md)。这不代表所有编辑器、输入法或 App 已通过验证。

本地证据（git 忽略）：首次为 `evidence/input-primitives-20260905-01.xcresult`、`build/stage4-input-test.log`；修正后为 `evidence/input-primitives-20260905-02.xcresult`、`build/stage4-input-corrected-test.log`。两次分别耗时 29.8、30.4 秒，包含保存层级与截图，不能当成文字输入耗时。CLI 的清空失败与成功分别保存在 `evidence/actions-cli-20260905-02/` 和 `evidence/actions-cli-20260905-03/`。
