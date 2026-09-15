---
name: kanpeki-imagegen
description: カンペきの画面モックや画像素材を生成・編集し、プロンプトと画像をチーム共有するときに使う。
---

Read `assets/design/README.md` and `docs/CODEX.md`. Use an available built-in image generation tool for raster generation/editing. Inspect local reference images before editing. Follow that tool's reference-image and output handling rules.
Do not claim that this skill installs the tool or shares a subscription. If unavailable, report the missing capability and offer an authorized teammate or an explicitly chosen API workflow; never silently use paid API credentials.
Keep generated UI ideas distinct from implemented features. Preserve requested Japanese text and existing brand constraints. Save project output in `assets/design/<issue>-<slug>/` with versioned filenames and `prompt.md`; verify the saved result visually and link the PR from the issue. Do not upload private attendee photos, slide notes, or credentials as references without specific authorization.
Use SwiftUI/SVG for simple code-native UI/icons when raster generation is unnecessary. Do not copy machine-specific paths or the user's entire installed skill library.
