# 全ドキュメントの棚卸し

2026-09-15、Issue #74。基準main：`e13496be9f5ec2a56cc79ba3e2b28f4c330dbbb0`（QR/承認/UI簡素化/文書更新ルールを含む）。trackedのMarkdown・txt・rst・adocを列挙し、以下84件を分類した。新規の本書を含め85件。未マージPRの文書はmain収録数へ含めず[STATUS](STATUS.md)で別記する。

「全更新」は全ファイルを機械的に変更することではない。現在の誤った断定を直し、正しい仕様・履歴・生成プロンプト・テンプレートは維持する。画像/動画とJSONモデルメタデータは文書数の対象外で、成果物・歴史値として保持した。trackedの独立LICENSE/NOTICE/COPYINGファイルは確認されず、各文書内の権利・配布元参照は維持。秘密情報・原資料は追加しない。

| ファイル | 分類 | 扱い |
|---|---|---|
| [.agents/skills/kanpeki-facilitator/SKILL.md](../.agents/skills/kanpeki-facilitator/SKILL.md) | 参照・維持 | 共有skill。製品の現在状態を記録する文書ではない |
| [.agents/skills/kanpeki-imagegen/SKILL.md](../.agents/skills/kanpeki-imagegen/SKILL.md) | 参照・維持 | 共有skill。製品の現在状態を記録する文書ではない |
| [.agents/skills/kanpeki-native/SKILL.md](../.agents/skills/kanpeki-native/SKILL.md) | 参照・維持 | 共有skill。製品の現在状態を記録する文書ではない |
| [.agents/skills/kanpeki-team/SKILL.md](../.agents/skills/kanpeki-team/SKILL.md) | 参照・維持 | 共有skill。製品の現在状態を記録する文書ではない |
| [.agents/skills/presentation-dialogue/SKILL.md](../.agents/skills/presentation-dialogue/SKILL.md) | 参照・維持 | 共有skill。製品の現在状態を記録する文書ではない |
| [.github/pull_request_template.md](../.github/pull_request_template.md) | 別担当更新済み | PR #76のルール。参照のみ、#74では編集しない |
| [AGENTS.md](../AGENTS.md) | 別担当更新済み | PR #76のルール。参照のみ、#74では編集しない |
| [README.md](../README.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [assets/design/45-mascot-animation/PROMPTS.md](../assets/design/45-mascot-animation/PROMPTS.md) | 生成履歴維持 | 生成原文・条件を現在の実装に書き換えない |
| [assets/design/45-mascot-animation/README.md](../assets/design/45-mascot-animation/README.md) | 企画・素材維持 | 配置目標/素材/非採用案。実機画面ではない |
| [assets/design/README.md](../assets/design/README.md) | 企画・素材維持 | 配置目標/素材/非採用案。実機画面ではない |
| [assets/design/archive/README.md](../assets/design/archive/README.md) | 企画・素材維持 | 配置目標/素材/非採用案。実機画面ではない |
| [assets/design/archive/kanpeki-layout-proposal-20260915-prompt.txt](../assets/design/archive/kanpeki-layout-proposal-20260915-prompt.txt) | 生成履歴維持 | 生成原文・条件を現在の実装に書き換えない |
| [assets/design/assistance/PROMPTS.md](../assets/design/assistance/PROMPTS.md) | 生成履歴維持 | 生成原文・条件を現在の実装に書き換えない |
| [assets/design/device-size/LAYOUT.md](../assets/design/device-size/LAYOUT.md) | 企画・素材維持 | 配置目標/素材/非採用案。実機画面ではない |
| [assets/design/device-size/PROMPTS.md](../assets/design/device-size/PROMPTS.md) | 生成履歴維持 | 生成原文・条件を現在の実装に書き換えない |
| [assets/design/screen-flow/PROMPTS.md](../assets/design/screen-flow/PROMPTS.md) | 生成履歴維持 | 生成原文・条件を現在の実装に書き換えない |
| [docs/AI_TEAM.md](../docs/AI_TEAM.md) | 調査・維持 | 限定範囲を確認。個別仕様・手順は維持 |
| [docs/APP_SETUP.md](../docs/APP_SETUP.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/AUDIO_CAPTURE.md](../docs/AUDIO_CAPTURE.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/AUTOMATIC_DELIVERY.md](../docs/AUTOMATIC_DELIVERY.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/BRAND_UI.md](../docs/BRAND_UI.md) | 履歴＋現状注記 | 当時の実測・失敗・準備制限を保存。現状はSTATUS |
| [docs/CAMERA_DEVELOPMENT.md](../docs/CAMERA_DEVELOPMENT.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/CD.md](../docs/CD.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/CI_PREPARATION.md](../docs/CI_PREPARATION.md) | 履歴維持 | 当時の実測・失敗・準備制限を保存。現状はSTATUS |
| [docs/CODEX.md](../docs/CODEX.md) | 調査・維持 | 限定範囲を確認。個別仕様・手順は維持 |
| [docs/CODEX_EVIDENCE.md](../docs/CODEX_EVIDENCE.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/DELIVERY.md](../docs/DELIVERY.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/DOCUMENTATION_WORKFLOW.md](../docs/DOCUMENTATION_WORKFLOW.md) | 別担当更新済み | PR #76のルール。参照のみ、#74では編集しない |
| [docs/HANDOFF.md](../docs/HANDOFF.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/MAC_INSTALL.md](../docs/MAC_INSTALL.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/MAC_TESTFLIGHT.md](../docs/MAC_TESTFLIGHT.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/MERGE.md](../docs/MERGE.md) | 別担当更新済み | PR #76のルール。参照のみ、#74では編集しない |
| [docs/MIGRATION.md](../docs/MIGRATION.md) | 履歴＋現状注記 | 当時の実測・失敗・準備制限を保存。現状はSTATUS |
| [docs/PEER_APPROVAL.md](../docs/PEER_APPROVAL.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/POINTER_DEVELOPMENT.md](../docs/POINTER_DEVELOPMENT.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/PORTABILITY.md](../docs/PORTABILITY.md) | 調査・維持 | 限定範囲を確認。個別仕様・手順は維持 |
| [docs/POWERPOINT_VALIDATION.md](../docs/POWERPOINT_VALIDATION.md) | 調査・維持 | 限定範囲を確認。個別仕様・手順は維持 |
| [docs/PREPARATION.md](../docs/PREPARATION.md) | 履歴維持 | 当時の実測・失敗・準備制限を保存。現状はSTATUS |
| [docs/QR_CONNECTION.md](../docs/QR_CONNECTION.md) | 調査・維持 | 限定範囲を確認。個別仕様・手順は維持 |
| [docs/RESULTS_DEVELOPMENT.md](../docs/RESULTS_DEVELOPMENT.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/SCREEN_REVIEW.md](../docs/SCREEN_REVIEW.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/SETUP.md](../docs/SETUP.md) | 履歴＋現状注記 | 当時の実測・失敗・準備制限を保存。現状はSTATUS |
| [docs/SLACK.md](../docs/SLACK.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/SLACK_DELIVERY.md](../docs/SLACK_DELIVERY.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/SLIDE_FRAME_SYNC.md](../docs/SLIDE_FRAME_SYNC.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/STATUS.md](../docs/STATUS.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/SUBMISSION.md](../docs/SUBMISSION.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/TEAM.md](../docs/TEAM.md) | 調査・維持 | 限定範囲を確認。個別仕様・手順は維持 |
| [docs/TEAM_WORKFLOW.md](../docs/TEAM_WORKFLOW.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/TESTFLIGHT_NOTES.txt](../docs/TESTFLIGHT_NOTES.txt) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [docs/WORKTREES.md](../docs/WORKTREES.md) | 調査・維持 | 限定範囲を確認。個別仕様・手順は維持 |
| [experiments/AudioCapture/README.md](../experiments/AudioCapture/README.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [experiments/AudioCapture/docs/INTEGRATION.md](../experiments/AudioCapture/docs/INTEGRATION.md) | 調査・維持 | 限定範囲を確認。個別仕様・手順は維持 |
| [experiments/AudioCapture/docs/VALIDATION.md](../experiments/AudioCapture/docs/VALIDATION.md) | 履歴＋現状注記 | 当時の実測・失敗・準備制限を保存。現状はSTATUS |
| [experiments/SlidePacer/README.md](../experiments/SlidePacer/README.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [experiments/SlidePacer/docs/LLM_SHARING.md](../experiments/SlidePacer/docs/LLM_SHARING.md) | 調査・維持 | 限定範囲を確認。個別仕様・手順は維持 |
| [experiments/SlidePacer/docs/TEAM_SETUP.md](../experiments/SlidePacer/docs/TEAM_SETUP.md) | 調査・維持 | 限定範囲を確認。個別仕様・手順は維持 |
| [experiments/SlidePacer/docs/VALIDATION.md](../experiments/SlidePacer/docs/VALIDATION.md) | 履歴＋現状注記 | 当時の実測・失敗・準備制限を保存。現状はSTATUS |
| [infrastructure/template/AGENTS.md](../infrastructure/template/AGENTS.md) | 別担当調整中 | #75でexport運用ルールを補修。#74では編集しない |
| [infrastructure/template/README.md](../infrastructure/template/README.md) | テンプレート維持 | 別repoの生成前初期状態。本repoの未実装という意味ではない |
| [infrastructure/template/docs/AI_TEAM.md](../infrastructure/template/docs/AI_TEAM.md) | テンプレート維持 | 別repoの生成前初期状態。本repoの未実装という意味ではない |
| [infrastructure/template/docs/CD.md](../infrastructure/template/docs/CD.md) | テンプレート修正 | 別repoの生成前初期状態。本repoの未実装という意味ではない |
| [infrastructure/template/docs/MAC_INSTALL.md](../infrastructure/template/docs/MAC_INSTALL.md) | テンプレート維持 | 別repoの生成前初期状態。本repoの未実装という意味ではない |
| [infrastructure/template/docs/SLACK.md](../infrastructure/template/docs/SLACK.md) | テンプレート維持 | 別repoの生成前初期状態。本repoの未実装という意味ではない |
| [infrastructure/template/docs/STATUS.md](../infrastructure/template/docs/STATUS.md) | テンプレート維持 | 別repoの生成前初期状態。本repoの未実装という意味ではない |
| [infrastructure/template/docs/TEAM.md](../infrastructure/template/docs/TEAM.md) | テンプレート維持 | 別repoの生成前初期状態。本repoの未実装という意味ではない |
| [infrastructure/template/docs/TESTFLIGHT_NOTES.txt](../infrastructure/template/docs/TESTFLIGHT_NOTES.txt) | テンプレート維持 | 別repoの生成前初期状態。本repoの未実装という意味ではない |
| [infrastructure/template/infrastructure/BUILD_CONTRACT.md](../infrastructure/template/infrastructure/BUILD_CONTRACT.md) | テンプレート維持 | 別repoの生成前初期状態。本repoの未実装という意味ではない |
| [infrastructure/template/infrastructure/SETUP.md](../infrastructure/template/infrastructure/SETUP.md) | テンプレート維持 | 別repoの生成前初期状態。本repoの未実装という意味ではない |
| [infrastructure/template/specs/FEATURE_TEMPLATE.md](../infrastructure/template/specs/FEATURE_TEMPLATE.md) | テンプレート維持 | 別repoの生成前初期状態。本repoの未実装という意味ではない |
| [integrations/slack/README.md](../integrations/slack/README.md) | 調査・維持 | 限定範囲を確認。個別仕様・手順は維持 |
| [specs/ARCHITECTURE.md](../specs/ARCHITECTURE.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [specs/ASSISTANCE_FLOW.md](../specs/ASSISTANCE_FLOW.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [specs/BRAND.md](../specs/BRAND.md) | 調査・維持 | 限定範囲を確認。個別仕様・手順は維持 |
| [specs/CAMERA_ANALYSIS.md](../specs/CAMERA_ANALYSIS.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [specs/FEATURE_TEMPLATE.md](../specs/FEATURE_TEMPLATE.md) | 仕様テンプレート維持 | 未記入欄は製品残件の一覧ではない |
| [specs/FILLER_CHAPTERS.md](../specs/FILLER_CHAPTERS.md) | 調査・維持 | 限定範囲を確認。個別仕様・手順は維持 |
| [specs/MINIMAL_UI.md](../specs/MINIMAL_UI.md) | 調査・維持 | 限定範囲を確認。個別仕様・手順は維持 |
| [specs/PRESENTATION_NOTIFICATIONS.md](../specs/PRESENTATION_NOTIFICATIONS.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [specs/PRESENTATION_TIMER.md](../specs/PRESENTATION_TIMER.md) | 調査・維持 | 限定範囲を確認。個別仕様・手順は維持 |
| [specs/PRODUCT.md](../specs/PRODUCT.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [specs/SCREEN_FLOW.md](../specs/SCREEN_FLOW.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |
| [specs/STEPWISE_SETUP.md](../specs/STEPWISE_SETUP.md) | 現状更新 | main/未マージ/実機/配布の区別・操作・参照を修正 |

## 監査方法と限界

- tracked文書を列挙し、入口/仕様/検証記録/運用/企画履歴/テンプレートを分類。状態記述をmainコード・担当Issue・PR状態と照合した。
- STATUSは確認SHA/時刻のスナップショット。PR #58の音声カメラ統合はpush済み未マージで、以前の未公開報告と区別した。
- 相対Markdownリンクをローカル検査。テンプレートの生成時JSONはリンクから生成物の説明へ修正。外部ログイン後の到達性・提出先閲覧権限は未検証。
- 実機・実音声・実カメラ・Apple配布を再実行していない。過去の成功数を今回の試験結果にしない。
- コード/署名/CI/scriptsは本PRで変更しない。更新ルールは[DOCUMENTATION_WORKFLOW](DOCUMENTATION_WORKFLOW.md)（PR #76）。内容は自動保証されず、各機能PRで更新とレビューを続ける。
