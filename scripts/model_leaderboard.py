#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
模型排行榜生成器（方案 C：每日邮件简报 · MVP v1）
=================================================
数据源：OpenRouter GET https://openrouter.ai/api/v1/models （免 API key）
产出：
  1. reports/模型排行榜_YYYY-MM-DD.html   人类可读简报（邮件正文/附件）
  2. reports/data/leaderboard_YYYY-MM-DD.json 机器可读摘要（供趋势对比）

四榜：
  ① 推理能力榜   按人工静态能力分降序
  ② 性价比榜     能力分 ÷ 混合单价，归一化 0–100 指数（只收近 180 天上线）
  ③ 价格榜       混合单价升序（免费单列）
  ④ 新秀雷达     近 30 天上线的模型，上线时间降序

公式：
  混合单价 BlendedPrice = 0.75 × 输入价 + 0.25 × 输出价（$/M token）
  性价比 Value          = 能力分 / BlendedPrice
  性价比指数            = Value / 榜内最高 Value × 100

容错（沿用重置雷达契约）：抓取失败 / 空数据 → 保留上一份好数据。
"""

import argparse
import datetime
import glob
import html
import json
import os
import re
import sys
import time
import urllib.request

BASE = "/Volumes/SSD-1TB/06-工具与开发/Ai算力条监控"
DATA_DIR = os.path.join(BASE, "reports", "data")
SRC_URL = "https://openrouter.ai/api/v1/models"
RADAR_DAYS = 30
# 性价比榜只收近半年上线的模型：旧低价模型会长期霸榜，但已无推荐价值。
VALUE_DAYS = 180

# ---------------------------------------------------------------------------
# 人工静态能力表（2026-10 基线，需每周人工校准；满分 100 = 当期最强公开模型）
# 与 Sources/CodexPetEnergy/ModelLeaderboardEngine.swift 的 capability 同源，
# 改一处必须同步另一处。
# 2026-10-25 代际更新：新一代旗舰入表（GPT-6.1-Sol / Claude Opus 5.5 /
# Gemini 4 Argon / GPT-5.2 / GPT-5.5 / Qwen3.5-Plus），上代 ≥94 分各降 4–5 分。
# 匹配规则：对 model id 做子串匹配，取最长命中项，避免 'v4' 误中 'v4.1'。
# ---------------------------------------------------------------------------
CAPABILITY = {
    # 新一代（2026-09/10）
    "gpt-6.1-sol-pro": 100,
    "claude-opus-5.5": 99,
    "gpt-6.1-sol": 98,
    "gemini-4-argon": 98,
    "gpt-5.2-codex": 96,
    "claude-opus-5": 95,
    "gpt-5.5-pro": 95,
    "gpt-5.2-pro": 94,
    "gpt-5.5": 93,
    "gpt-5.2-chat": 92,
    "qwen3.5-plus": 92,
    # 上代旗舰（2026-10-25 各降 4–5 分）
    "gpt-5.1-codex-max": 96,
    "gpt-5.1-codex": 95,
    "claude-opus-4.5": 95,
    "gemini-3-pro": 95,
    "grok-4.1": 94,
    "kimi-k3.1-pro": 94,
    "kimi-k3.1": 92,
    "gpt-5.1": 94,
    "gpt-5-pro": 93,
    "gpt-5-codex": 93,
    "claude-sonnet-4.5": 93,
    "deepseek-v4.1-pro": 93,
    "gemini-2.5-pro": 92,
    "grok-4": 92,
    "claude-opus-4.1": 92,
    "glm-5": 92,
    "qwen3-max": 91,
    "claude-sonnet-4": 90,
    "gpt-5": 92,
    "deepseek-v4.1": 90,
    "deepseek-v4": 89,
    "minimax-m2": 89,
    "doubao-seed-2.0-pro": 89,
    "gemini-3-flash": 90,
    "deepseek-reasoner": 89,
    "gpt-5-mini": 87,
    "codex-mini": 88,
    "qwen3-coder-plus": 88,
    "glm-4.6": 88,
    "kimi-k2-thinking": 87,
    "grok-4-fast": 87,
    "minimax-m3.1-flash": 86,
    "deepseek-v3.2": 86,
    "deepseek-chat": 86,
    "qwen3-235b": 86,
    "claude-haiku-4.5": 86,
    "glm-4.5": 86,
    "kimi-k2": 85,
    "grok-code-fast": 85,
    "mistral-large-3": 85,
    "gemini-2.5-flash": 85,
    "deepseek-r1": 85,
    "nemotron": 83,
    "doubao-seed-2.0-lite": 83,
    "doubao-seed-1.6": 82,
    "glm-4.5-air": 82,
    "mercury-3": 82,
    "o4-mini": 82,
    "claude-3.5-sonnet": 82,
    "minimax-m1": 82,
    "magistral-medium": 81,
    "qwen3-30b": 81,
    "llama-4-maverick": 84,
    "llama-4-scout": 79,
    "ernie-5.0": 84,
    "ernie-4.5": 79,
    "gemini-2.0-flash": 79,
    "codestral": 79,
}


def fetch_models(use_cache: bool):
    """抓取全量模型；失败或空则回退最近一份缓存。返回 (models, source, fetched_at)。"""
    raw = None
    try:
        req = urllib.request.Request(SRC_URL, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = json.loads(resp.read().decode("utf-8"))
        if not raw.get("data"):
            raise ValueError("empty data payload")
    except Exception as exc:  # noqa: BLE001
        print(f"[warn] live fetch failed: {exc}", file=sys.stderr)
        raw = None

    if raw is None:
        cache = sorted(glob.glob(os.path.join(DATA_DIR, "openrouter_models_*.json")))
        if not cache:
            raise SystemExit("live fetch failed and no cached payload available")
        with open(cache[-1], encoding="utf-8") as fh:
            raw = json.load(fh)
        source = f"cache:{os.path.basename(cache[-1])}"
    else:
        source = "live:" + SRC_URL

    now = datetime.datetime.now()
    snapshot = os.path.join(DATA_DIR, f"openrouter_models_{now:%Y-%m-%d}.json")
    if raw.get("data") and (source.startswith("live") or not glob.glob(snapshot)):
        os.makedirs(DATA_DIR, exist_ok=True)
        with open(snapshot, "w", encoding="utf-8") as fh:
            json.dump(raw, fh)
    return raw["data"], source, now


def capability_of(model_id: str):
    best, best_len = None, 0
    for key, score in CAPABILITY.items():
        if key in model_id and len(key) > best_len:
            best, best_len = score, len(key)
    return best


def blended_price(pricing: dict) -> float:
    """混合单价 $/M token：0.75 输入 + 0.25 输出。"""
    try:
        pin = float(pricing.get("prompt") or 0)
        pout = float(pricing.get("completion") or 0)
    except (TypeError, ValueError):
        return 0.0
    return round((0.75 * pin + 0.25 * pout) * 1_000_000, 4)


def fmt_price(v: float) -> str:
    if v <= 0:
        return "免费"
    if v < 0.01:
        return f"${v:.5f}"
    if v < 1:
        return f"${v:.3f}"
    return f"${v:.2f}"


def fmt_ctx(n):
    if not n:
        return "—"
    if n >= 1_000_000:
        return f"{n / 1_000_000:g}M"
    return f"{n // 1024}K"


def build_rows(models):
    rows = []
    for m in models:
        mid = m.get("id", "")
        pricing = m.get("pricing", {}) or {}
        vendor = mid.split("/", 1)[0] if "/" in mid else mid
        price = blended_price(pricing)
        try:
            created = int(m.get("created") or 0)
        except (TypeError, ValueError):
            created = 0
        rows.append({
            "id": mid,
            "name": m.get("name") or mid,
            "vendor": vendor,
            "context": m.get("context_length") or 0,
            "in": pricing.get("prompt"),
            "out": pricing.get("completion"),
            "price": price,
            "free": price <= 0,
            # 图像模型判定只看输出模态：pricing 带 image 价只说明「图像输入」收费
            # （如 Gemini 4 Argon 多模态文本模型），不能作为排除依据。
            "image": "image" in (m.get("architecture", {}) or {}).get("output_modalities", []),
            "batch": "batch" in mid.lower(),
            "created": created,
            "created_str": datetime.datetime.fromtimestamp(created, datetime.timezone.utc).strftime("%Y-%m-%d") if created > 0 else "—",
            "score": capability_of(mid),
            "desc": re.sub(r"\s+", " ", (m.get("description") or "")).strip()[:160],
        })
    return rows


def rank(rows, now):
    radar_cutoff = (now - datetime.timedelta(days=RADAR_DAYS)).timestamp()
    radar = sorted(
        [r for r in rows if r["created"] > 0 and r["created"] >= radar_cutoff],
        key=lambda r: r["created"], reverse=True,
    )
    cap_all = [r for r in rows if r["score"] and not r["image"] and not r["batch"]]
    cap = sorted(cap_all, key=lambda r: -r["score"])
    value_cutoff = (now - datetime.timedelta(days=VALUE_DAYS)).timestamp()
    valued = [r for r in cap if not r["free"] and r["created"] >= value_cutoff]
    for r in valued:
        r["value"] = r["score"] / r["price"]
    vmax = max((r["value"] for r in valued), default=1) or 1
    for r in valued:
        r["value_index"] = round(r["value"] / vmax * 100, 1)
    value = sorted(valued, key=lambda r: -r["value"])
    paid = sorted([r for r in rows if not r["free"]], key=lambda r: r["price"])
    free = sorted([r for r in rows if r["free"]], key=lambda r: -r["context"])
    return radar, cap, value, paid, free


def table(rows, cols, row_attrs=None):
    head = "".join(f"<th>{c}</th>" for c in cols)
    body = []
    for r in rows:
        attrs = row_attrs(r) if row_attrs else ""
        body.append("<tr" + (f" {attrs}" if attrs else "") + ">" + "".join(f"<td>{v}</td>" for v in r["_cells"]) + "</tr>")
    return f'<table><thead><tr>{head}</tr></thead><tbody>{"".join(body)}</tbody></table>'


def esc(s):
    return html.escape(str(s), quote=True)


def render(date_str, source, rows, radar, cap, value, paid, free, now):
    def cells_price(r):
        def per_m(v):
            try:
                return float(v or 0) * 1e6
            except (TypeError, ValueError):
                return 0.0
        return [esc(r["name"]), esc(r["vendor"]), fmt_ctx(r["context"]), fmt_price(r["price"]), fmt_price(per_m(r["in"])), fmt_price(per_m(r["out"]))]

    def cells_cap(r):
        star = " ★" if r["created"] > 0 and r["created"] >= (now - datetime.timedelta(days=RADAR_DAYS)).timestamp() else ""
        return [f'{r["score"]}{star}', esc(r["name"]), esc(r["vendor"]), fmt_ctx(r["context"]), fmt_price(r["price"])]

    def cells_value(r):
        return [f'{r["value_index"]}', f'{r["score"]}', esc(r["name"]), esc(r["vendor"]), fmt_price(r["price"])]

    def cells_radar(r):
        star = " ★" if (r["score"] or 0) >= 92 or (r["score"] is None and r["free"]) else ""
        tag = " ·图像" if r["image"] else ""
        return [r["created_str"], esc(r["name"]) + tag, esc(r["vendor"]), fmt_ctx(r["context"]), fmt_price(r["price"]), (str(r["score"]) if r["score"] else "待标定") + star]

    for r in radar: r["_cells"] = cells_radar(r)
    for r in cap: r["_cells"] = cells_cap(r)
    for r in value: r["_cells"] = cells_value(r)
    for r in paid: r["_cells"] = cells_price(r)
    for r in free: r["_cells"] = cells_price(r)

    def section(title, note, t, limit=None, empty="（无）"):
        data = t if limit is None else t[:limit]
        if not data:
            body = f'<p class="empty">{empty}</p>'
        else:
            body = table(data, data[0]["_cols"])
        return f'<section><h2>{title}</h2><p class="note">{note}</p>{body}</section>'

    radar[:1] and radar[0].update({"_cols": ["上线日期", "模型", "提供方", "上下文", "混合单价", "能力分"]})
    cap[:1] and cap[0].update({"_cols": ["能力分", "模型", "提供方", "上下文", "混合单价"]})
    value[:1] and value[0].update({"_cols": ["性价比指数", "能力分", "模型", "提供方", "混合单价"]})
    paid[:1] and paid[0].update({"_cols": ["模型", "提供方", "上下文", "混合单价", "输入价", "输出价"]})
    free[:1] and free[0].update({"_cols": ["模型", "提供方", "上下文", "混合单价", "输入价", "输出价"]})

    n_free, n_paid, n_unscored = len(free), len(paid), sum(1 for r in rows if not r["score"])
    newest = max(radar, key=lambda r: r["created"]) if radar else None

    doc = f"""<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>模型排行榜 · {date_str}</title>
<style>
:root {{ --line:#d8d4cc; --muted:#6b6960; --accent:#185FA5; }}
* {{ box-sizing:border-box; }}
body {{ margin:0; padding:32px 20px; background:#faf9f6; color:#22201c;
  font:14px/1.6 -apple-system,"SF Pro SC","PingFang SC","Helvetica Neue",sans-serif; }}
.wrap {{ max-width:1080px; margin:0 auto; }}
header h1 {{ font-size:20px; margin:0 0 6px; }}
header p {{ margin:2px 0; color:var(--muted); font-size:13px; }}
section {{ background:#fff; border:1px solid var(--line); border-radius:10px; padding:20px 24px; margin-top:22px; }}
h2 {{ font-size:16px; margin:0 0 4px; }}
.note {{ margin:0 0 14px; color:var(--muted); font-size:12.5px; }}
table {{ width:100%; border-collapse:collapse; font-size:13px; }}
th {{ text-align:left; font-weight:500; color:var(--muted); border-bottom:1px solid var(--line); padding:8px 10px; white-space:nowrap; }}
td {{ padding:8px 10px; border-bottom:1px solid #efede7; vertical-align:top; }}
tr:last-child td {{ border-bottom:none; }}
td:nth-child(1) {{ white-space:nowrap; font-variant-numeric:tabular-nums; }}
.empty {{ color:var(--muted); }}
footer {{ margin:26px 0 0; color:var(--muted); font-size:12px; line-height:1.7; }}
.kpi {{ display:flex; flex-wrap:wrap; gap:12px; margin-top:18px; }}
.kpi div {{ flex:1 1 150px; background:#fff; border:1px solid var(--line); border-radius:10px; padding:12px 16px; }}
.kpi b {{ display:block; font-size:20px; font-weight:500; }}
.kpi span {{ color:var(--muted); font-size:12px; }}
</style></head><body><div class="wrap">
<header>
<h1>模型排行榜 · 每日简报</h1>
<p>{date_str} · 数据源：{esc(source)} · 共收录 {len(rows)} 个模型（收费 {n_paid} / 免费 {n_free}）</p>
<p>口径：混合单价 = 0.75×输入 + 0.25×输出（$/M token）；性价比 = 能力分 ÷ 混合单价；能力分为人工静态表（2026-10 基线，待每周校准，{n_unscored} 个模型未标定）。</p>
</header>
<div class="kpi">
<div><b>{len(radar)}</b><span>近 30 天新上线</span></div>
<div><b>{len(cap)}</b><span>已标定能力分</span></div>
<div><b>{len(value)}</b><span>可算性价比</span></div>
<div><b>{esc(newest['name']) if newest else '—'}</b><span>最新上线（{newest['created_str'] if newest else '—'}）</span></div>
</div>
{section("④ 新秀雷达 · 最近有什么新模型", "按上线时间倒序；★ = 能力分 ≥92 或免费未标定，建议优先试。", radar)}
{section("① 推理能力榜", "按人工静态能力分降序；★ = 近 30 天新上线。", cap, limit=40)}
{section("② 性价比榜", f"能力分 ÷ 混合单价，指数 100 = 本榜最强单位成本；只收近 {VALUE_DAYS} 天上线、已标定的收费模型，旧模型仍可在能力/价格榜查看。", value, limit=40)}
{section("③ 价格榜 · 收费模型", "混合单价升序，越靠前越「能随便造」。", paid, limit=40)}
{section("③ 价格榜 · 免费模型", f"按上下文长度降序，共 {n_free} 个。", free, limit=40)}
<footer>
口径与局限：价格来自 OpenRouter 聚合的各提供方标价，可能与官网直连价存在差异；能力分是人工静态表，
新模型（尤其近 30 天上线的）大量处于「待标定」状态，其排序仅供参考，请以实际体验为准。<br>
下次更新：{now + datetime.timedelta(days=1):%Y-%m-%d} 09:00（每日 1 次，抓取失败保留上一份好数据）。
</footer>
</div></body></html>"""
    return doc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", default=os.path.join(BASE, "reports"))
    ap.add_argument("--top", type=int, default=40)
    args = ap.parse_args()

    models, source, now = fetch_models(args.out_dir)
    rows = build_rows(models)
    radar, cap, value, paid, free = rank(rows, now)
    date_str = f"{now:%Y-%m-%d}"
    doc = render(date_str, source, rows, radar, cap, value, paid, free, now)

    os.makedirs(args.out_dir, exist_ok=True)
    html_path = os.path.join(args.out_dir, f"模型排行榜_{date_str}.html")
    with open(html_path, "w", encoding="utf-8") as fh:
        fh.write(doc)

    summary = {
        "date": date_str,
        "source": source,
        "total": len(rows),
        "radar_top": [{"name": r["name"], "vendor": r["vendor"], "created": r["created_str"],
                       "price": r["price"], "score": r["score"]} for r in radar[:20]],
        "capability_top": [{"name": r["name"], "score": r["score"]} for r in cap[:20]],
        "value_top": [{"name": r["name"], "index": r["value_index"], "score": r["score"], "price": r["price"]} for r in value[:20]],
        "price_cheapest": [{"name": r["name"], "price": r["price"]} for r in paid[:20]],
    }
    json_path = os.path.join(DATA_DIR, f"leaderboard_{date_str}.json")
    with open(json_path, "w", encoding="utf-8") as fh:
        json.dump(summary, fh, ensure_ascii=False, indent=2)

    print(f"models={len(rows)} radar={len(radar)} scored={len(cap)} valued={len(value)} paid={len(paid)} free={len(free)}")
    print(f"html={html_path}")
    print(f"json={json_path}")
    if radar:
        print("latest:", radar[0]["created_str"], radar[0]["name"])


if __name__ == "__main__":
    main()
