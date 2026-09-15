---
name: kanpeki-native
description: カンペきのSwiftUI、Mac画面取得、iPhone連携、PPTX発表者ノートや通信契約を変更するときに使う。
---

Read `README.md` and `docs/STATUS.md`. `Shared/Models.swift` defines the wire contract; capture comes from PowerPoint rather than a custom renderer. Preserve source-slide identity validation before showing notes.
Use `bash scripts/check.sh core`, and choose `mac` or `phone` for affected targets. Cross-platform contract changes require both builds. Signing is disabled in these checks; real-device pairing, screen recording, Apple Events, and slideshow navigation need separate validation.
Keep bounded frame transfer, explicit pairing approval, and disabled controls for stale state. Record actual tests and unavailable device checks in the task Issue and PR. Use worktree-local `.build` output. New Swift files must be included in the relevant Xcode target.
