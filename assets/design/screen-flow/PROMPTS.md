# ImageGen生成記録

内蔵ImageGenで生成した企画画像。アプリの実装画面ではない。画面の厳密な寸法・全遷移は仕様書で管理する。

screenFlowPromptPhone

Create a high fidelity Japanese UI storyboard, wide 2400x1600, 4 columns x 2 rows, eight portrait iPhone screens with thin outlines, large crisp readable labels, very sparse text. App カンペき, pale green #D9EBD5 backgrounds, ivory #F9FFE6 surfaces, slate #5C6673 text and controls; coral only time-expiry warning. Heading “iPhone｜接続から終了まで”, tiny “設計案・未実装”. IMPORTANT all slide-containing screens show a real 16:9 slide scaled to full inner width at the BOTTOM of the usable phone screen, directly above home indicator. NEVER any next/previous button or chevron; no navigation bar beneath slide. Preserve 16:9, no stretching. The lower slide itself is the tap/drag control. Include a subtle numbered slide “研究の背景” with simple circle arrow square illustration identical across phones. All other controls and notes appear ABOVE slide.
Eight panels:
1 labelled P01 “未接続”: small friendly notepad mascot app mark, short “Macとつなぐ” primary button, extensive empty space.
2 labelled P02 “QRで接続”: scanner frame in upper/middle, caption “MacのQRを読み取る”, small “カメラを使わず接続” at bottom, close x top.
3 labelled P03 “接続確認”: laptop icon, “発表用Mac”, short code “482 619”, “接続” button, no slide.
4 labelled P05 “発表準備”: connected icon, time “05:00”, small 手持ち / 固定 segmented control, prominent “発表開始” button ABOVE lower slide.
5 labelled P06 “手持ち発表”: connected icon top, big “02:40”, one short note “まず研究の背景を説明します。” in middle and lots of breathing room. Landscape slide flush near bottom. A small slate pointer dot and tiny motion trail inside slide, no arrows/buttons. OUTSIDE device BELOW label state “左タップで戻る｜右タップで進む” and “指を動かすとポインター”. No long press icons.
6 labelled P07 “固定発表”: small “撮影中” indicator and 02:40 at top, a small secondary grayscale abstract audience camera preview in middle, landscape slide at bottom. tiny ellipsis top menu, no next or previous buttons.
7 labelled E03 “再接続”: top compact “再接続中”, old slide desaturated at bottom labelled “操作できません”; no busy overlays or multiple CTAs. no slide forward buttons.
8 labelled P10 “終了”: big “発表終了”, time “05:12”, a single “準備に戻る” button; no fake scores or AI analytics.
Connect sequence panels with fine light gray arrows OUTSIDE phone frames only. Do not add invented slogans, excessive explanations or gradient decoration. Make bottom-positioned slide obvious with generous empty upper area and touch reach comfort. This is proposal storyboard, NOT code or screenshots of an implemented app.

---

screenFlowPhoneEditPrompt

Edit this storyboard only. Preserve the 8 phone layouts, Japanese state labels, slide-at-bottom placement, and no next/previous buttons. Fix three things: 1) In the handheld P06 screen change the red 02:40 timer to slate #5C6673; all normal timers slate, never coral. 2) Remove ALL arrows BETWEEN phone panels: these are a state catalogue, not a linear forced sequence, handheld and fixed are alternatives. Change title to “iPhone｜画面一覧” and add tiny “遷移は設計書を参照”. 3) Replace the invented smiling outlined mascot in P01 with the actual supplied notepad face logo from reference 2, matching that logo faithfully as a small square app icon. Remove green success badges and green text; use slate connection icon and short slate 接続済み instead to avoid unnecessary colors. Keep everything else unchanged; photo-free simple flat UI, no slogans, no added cards.

---

screenFlowPromptMac

Use case UI storyboard. Create Japanese app カンペき desktop and recovery states, wide 2400x1600, very readable 3 columns x 2 rows. Heading “MacとiPhone｜準備・復帰の画面”, tiny “設計案・未実装”. Flat frontend wireframes polished native UI, pale green #D9EBD5, ivory #F9FFE6, slate #5C6673. No gradients, no slogans, no mascot invention, no arrows BETWEEN panels. Each panel is a state catalogue, not a linear flow.
Top row 3 LANDSCAPE Mac windows:
M01 “準備ホーム”: simple empty large slide region and two primary actions “資料を選ぶ” and “iPhoneをつなぐ”, no dashboards.
M03 “iPhone接続”: compact centered modal over preparation home: title “iPhoneで読み取る”, large illustrative nonfunctional QR, tiny “接続用・サンプル”, device name “発表用Mac”, code “482 619”, close x. No real URLs or secrets.
M03a “接続承認”: small modal “このiPhoneを接続しますか？” device “発表者のiPhone”, code “482 619”, buttons “許可” and “拒否”. Underlying Mac slide preview remains.
Bottom row 3 panels:
M04 “Mac・発表準備”: landscape Mac window with large simple academic 16:9 slide “研究の背景” circle arrow square. Small top connected phone icon, timer 05:00 and “発表開始”. One short speaker note underneath slide. No prev/next buttons.
E01 “iPhone・権限から復帰”: portrait iPhone inside panel with minimal sheet “カメラを使用できません”, primary “設定を開く”, text action “カメラを使わず接続”, small “戻る”. This is app explanation NOT fake OS permission dialog.
P09 “iPhone・終了確認”: portrait iPhone with landscape slide pinned at very bottom above home indicator, top 02:40, middle compact confirmation sheet “発表を終了しますか？” with “終了” and “続ける”. No next or previous arrows or buttons on any phone. Upper menu and sheet must not obscure bottom slide.
Lots of whitespace, use short exact Japanese strings, all normal timers slate. No AI scoring or fake analysis, no auto-deploy UI. Product mockup stateboard, not implemented application.

---

screenFlowMacEditPrompt

Edit this UI stateboard. Keep layout, text, device frames, QR sample, slide placement unchanged. Change ALL saturated green button fills (資料を選ぶ, 許可, 発表開始, 設定を開く, 終了) to the exact slate #5C6673. White button text stays white. Keep background pale green #D9EBD5 and ivory #F9FFE6 surfaces. Remove the explanatory paragraph inside the E01 camera denied sheet; retain only カメラを使用できません plus the three actions, reducing text. Keep all content fully inside image boundaries including bottom of both phones (add small bottom whitespace if needed). Do not add any next/previous button, new colors, diagrams, or marketing copy.
