# Explicit Runner actions

Requires CLI 0.4.0 with action protocol 13 and its matching Runner. Preflight must report `Explicit Runner actions: available`; otherwise upgrade and reconnect rather than guessing old semantics. Standard mode retains its native-text reference.

Every example uses a placeholder CURRENT from the latest successful observation. Read its image before the next input; do not execute these as a batch.

Prefer direct XCTest input with `type CURRENT --text TEXT --observe`, omitting `--method`. `textMethods: ["touch-paste"]` lists the optional explicit method, not all typing capabilities; it does not disable default element typing. Confirm focus from current evidence; an extra `focus` call is unnecessary when the exact field already demonstrably owns keyboard focus. The backend still validates identity and focus immediately before input.

Use [touch paste](touch-paste.md) only when explicitly requested or supported by a concrete limitation of direct typing (for example, an app known to close its editor on keyboard changes, or no usable AX element for an editable field). Do not run an input known to be unsuitable just to qualify for fallback. Length, language and emoji alone do not establish such a limitation. A stale target or missing focus calls for a fresh observation or focus correction, not a switch of input method. After a timeout, `unknown`, partial text or failed observation, inspect the field and preserve existing input; switching methods must not replay the original text. If content or placement cannot be established, stop rather than guessing a remainder.

- Focus: `focus CURRENT --observe`. Inspect `result.inputAction.verification` and the image. Already focused is a no-op. A tap may navigate; choose a new target from the new page, never retry focus blindly.
- Insert: `type CURRENT --text TEXT --observe`. Requires that exact target to own keyboard focus; does not tap, clear or position. Input is sent once. Check actual text; no final-value guarantee.
- Replace: focus and inspect; `press CURRENT --key select-all --observe`; verify selection; `clear CURRENT --observe`; require empty field; then type and inspect. Clear sends one Delete only, never selects or repairs incomplete selection. A missing pre-input AX value rejects as `clear_value_unavailable`; it does not prove emptiness. Do not continue unless emptiness is confirmed.
- Append: focus and inspect; `press CURRENT --key end --observe`; verify end position and unchanged original text; type only the suffix and inspect. If the end/selection cannot be established visually or from AX, stop or choose a visible UI operation. Never clear/rewrite to append.
- Editing keys require the specified field to own focus. Return/Tab may submit or change focus; inspect before proceeding.
- Element gestures bind the current identity, not the old center. Coordinates require current screenshot geometry and protected local pixels. Runner's global threshold defaults to 1, local to 0; standard defaults are unchanged. Neither proves business identity.

Sibling insertion/removal and layout changes are allowed while the original ancestor identity chain remains. Replacement, reparenting or ambiguity reject instead of selecting a similar element. New observations invalidate old references.

Execution and observation are independent. `completed` confirms execution or a verified no-op, not business success. `inputAction.verification=unconfirmed/unavailable` means focus/clear effects need inspection. `observationError` or a failing combined `--observe` exit must not trigger another input. `unknown` may include partial input: inspect actual contents and preserve progress. Never restart the entire replace workflow after a late failure. No automatic replay or cross-app identity fallback.
