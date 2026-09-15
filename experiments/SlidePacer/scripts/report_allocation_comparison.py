"""Compare saved complete runs against an editorial reference, not an accuracy score."""
from pathlib import Path
import argparse, hashlib, json, statistics

p = argparse.ArgumentParser()
p.add_argument('--out', required=True)
a = p.parse_args()
out = Path(a.out)
root = Path('evaluation')
source_hash = hashlib.sha256(Path('SlidePacer/ContentView.swift').read_bytes()).hexdigest()
cases = [
    ('WN', 'wn', 'wn-reference.json', 'extractive-final/plan.json'),
    ('研究資料', 'research', 'second-deck/reference.json', 'second-deck/plan.json'),
]
lines = ['# 時間配分の再評価（2026-09-10）', '',
    '前回と同じ資料・Qwen3.5:9bで、全40ページの原文選択を新しい指示で再実行。全体の重点候補は前回の応答を固定し、誤った候補に引きずられないか確認した。モデルの重みは変更していない。', '',
    '人の基準は事前に作成した編集案であり唯一の正解ではない。平均絶対秒差は配分の近さを示し、要約の正解率ではない。この2資料を使った調整なので、未知の資料への一般化は未確認。', '',
    '|資料|全体比較を入れる前|前回|今回|合計|省略ページ（前回→今回）|',
    '|---|---:|---:|---:|---:|---|']
rows = []
for label, name, ref_path, early_path in cases:
    folder = out / name
    read = lambda path: json.loads(path.read_text())
    ref = read(root / ref_path)
    early = read(root / early_path)
    previous = read(root / ('final-' + name) / 'result.json')['plan']
    plan = read(folder / 'plan.json')
    records = read(folder / 'records.json')
    requests = read(folder / 'requests.json')
    assert len(records) == len(requests) == len(ref['slides'])
    assert all(r['request'] == q['request'] for r, q in zip(records, requests))
    for r in records:
        selection = json.loads(r['response']['response'])
        assert r['response'].get('done_reason') != 'length'
        assert set(selection['coreIDs'] + selection['detailIDs']) <= {p['id'] for p in r['points']}
    def mae(plan):
        return statistics.mean(abs(s['recommendedSeconds'] - r['seconds']) for s, r in zip(plan['slides'], ref['slides']))
    def skipped(plan):
        return [s['slideIndex'] for s in plan['slides'] if s['recommendedSeconds'] == 0]
    total = sum(s['recommendedSeconds'] for s in plan['slides'])
    assert total == 600
    duplicates = [r['slideIndex'] for r in records if len((s := json.loads(r['response']['response']))['coreIDs'] + s['detailIDs']) != len(set(s['coreIDs'] + s['detailIDs']))]
    budget_metrics = {}
    for budget in [180, 600, 900]:
        b = plan if budget == 600 else read(folder / f'plan-{budget}.json')
        seconds = sum(s['recommendedSeconds'] for s in b['slides'])
        assert seconds == budget
        budget_metrics[budget] = {'totalSeconds': seconds, 'skippedPages': skipped(b)}
    metrics = {'earlyMeanAbsoluteSecondsDifference': mae(early), 'previousMeanAbsoluteSecondsDifference': mae(previous),
        'meanAbsoluteSecondsDifference': mae(plan), 'totalSeconds': total, 'skippedPages': skipped(plan),
        'duplicateIDPagesBeforeDeduplication': duplicates, 'pageGenerationElapsedSeconds': sum(r['elapsedSeconds'] for r in records), 'budgets': budget_metrics}
    result = {'status': 'evaluated-improvement-on-two-tuning-decks', 'model': 'qwen3.5:9b', 'budgetSeconds': 600,
        'codeSHA256': source_hash, 'input': read(folder / 'slides.json'), 'direction': read(folder / 'direction.json'),
        'pageRecords': records, 'pageBriefs': read(folder / 'page-briefs.json'), 'plan': plan, 'evaluation': metrics,
        'notes': 'Global selection reused from previous run; all local selections regenerated. Editorial time slots, not measured speech duration. No UI, OCR or unseen-deck evaluation.'}
    (folder / 'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2))
    lines.append(f'|{label}|{mae(early):.1f}秒/頁|{mae(previous):.1f}秒/頁|{mae(plan):.1f}秒/頁|{total}秒|{skipped(previous)} → {skipped(plan)}|')
    rows.append((label, ref, previous, plan, metrics))
lines += ['', '## 変更と検証', '',
    '- 全体LLMの「補足」判定だけで、課題・全体像・主要機能の重要度を最低へ落とさない。重点候補による主要機能への加点も抑えた。',
    '- ページ読解へ固定の重要度を押し付けず、内容から役割を判断させる。結果では比較表のモデル名・指標・数値を選ぶよう指示した。',
    '- 句点の少なさで説明時間を制限せず、短い箇条書きの説明にも枠を使えるようにした。',
    '- 発表者ノートがあっても、本文だけにある否定・評価条件を保持する。これはキーワードによる補助処理であり、LLM単独の理解とは区別する。',
    '- 23件の回帰テストとSwift全体の型チェックを実行。両資料を180・600・900秒で配分し、合計を確認。',
    '- 原文IDの重複はなお発生し、コードで統合している。元の出力はresult.jsonに保存。生成上限到達・未知IDは今回なし。',
    '- 秒数は説明枠であり、表示された原文抜粋をすべて読み上げるための実測時間ではない。', '',
    '意味内容の確認は [content-review.md](content-review.md) に記載。']
for label, ref, previous, plan, metrics in rows:
    lines += ['', f'## {label}', '',
        f'ページ選択の実測合計: {metrics["pageGenerationElapsedSeconds"]:.1f}秒（全体選択・UI処理は含めない）。', '',
        '|頁|人の基準|前回|今回|', '|---|---:|---:|---:|']
    for r, old, new in zip(ref['slides'], previous['slides'], plan['slides']):
        lines.append(f'|{r["slideIndex"]}|{r["seconds"]}|{old["recommendedSeconds"]}|{new["recommendedSeconds"]}|')
(out / 'comparison.md').write_text('\n'.join(lines) + '\n')
print(out / 'comparison.md')
