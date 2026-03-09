#!/usr/bin/env bash
# 卖家精灵选品 AI 分析脚本
# Usage: analyze.sh <data_json_file> <query> <marketplace> [--output file.md]

set -euo pipefail

DATA_FILE="${1:-}"
QUERY="${2:-unknown}"
MARKETPLACE="${3:-US}"
OUTPUT_FILE=""
MODEL_ARG=""

shift 3 || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    --model) MODEL_ARG="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# 模型别名映射
resolve_model() {
  local m="$1"
  case "$m" in
    claude|claude-sonnet)          echo "anthropic/claude-sonnet-4-6" ;;
    claude-opus)                   echo "anthropic/claude-opus-4-6" ;;
    claude-haiku)                  echo "anthropic/claude-haiku-4-5" ;;
    claude-3-7|claude-3-7-sonnet)  echo "anthropic/claude-3-7-sonnet-latest" ;;
    gemini|gemini-pro)             echo "google/gemini-2.5-pro" ;;
    gemini-flash)                  echo "google/gemini-2.5-flash" ;;
    gemini-3|gemini-3-pro)         echo "google/gemini-3-pro-preview" ;;
    gpt-4o)                        echo "openai/gpt-4o" ;;
    gpt-4.1)                       echo "openai/gpt-4.1" ;;
    gpt-5|gpt5)                    echo "openai/gpt-5" ;;
    gpt-5.2|gpt52)                 echo "openai/gpt-5.2" ;;
    o3)                            echo "openai/o3" ;;
    o4-mini)                       echo "openai/o4-mini" ;;
    grok|grok-4)                   echo "xai/grok-4" ;;
    grok-3)                        echo "xai/grok-3" ;;
    grok-3-mini)                   echo "xai/grok-3-mini" ;;
    deepseek|deepseek-r1)          echo "groq/deepseek-r1-distill-llama-70b" ;;
    qwen|qwen3)                    echo "groq/qwen/qwen3-32b" ;;
    mistral|mistral-large)         echo "mistral/mistral-large-latest" ;;
    llama|llama4)                  echo "groq/meta-llama/llama-4-maverick-17b-128e-instruct" ;;
    venice)                        echo "venice/claude-sonnet-4-6" ;;
    *)                             echo "$m" ;;  # 透传完整 model ID
  esac
}

if [[ -z "$DATA_FILE" || ! -f "$DATA_FILE" ]]; then
  echo "❌ 需要提供数据文件" >&2
  exit 1
fi

if ! command -v openclaw &>/dev/null; then
  echo "openclaw not found. Please install OpenClaw first." >&2
  exit 1
fi

TODAY=$(date +%Y-%m-%d)

# 读取并精简数据给 AI
DATA_SUMMARY=$(python3 - <<PYEOF
import json, sys

with open('$DATA_FILE') as f:
    data = json.load(f)

stats = data.get('stats', {})
products = data.get('products', [])
keywords = data.get('keywords', [])
query = data.get('query', {})

# 精简产品列表（给 AI 的）
top_products = products[:30]
simplified = []
for p in top_products:
    simplified.append({
        'asin': p.get('asin'),
        'brand': p.get('brand'),
        'title': (p.get('title') or '')[:80],
        'price': p.get('price'),
        'units': p.get('units'),
        'revenue': p.get('revenue'),
        'ratings': p.get('ratings'),
        'rating': p.get('rating'),
        'bsr': p.get('bsr'),
        'fulfillment': p.get('fulfillment'),
        'sellers': p.get('sellers'),
        'badge': p.get('badge', {}),
    })

# 精简关键词
top_kw = []
for kw in keywords[:15]:
    top_kw.append({
        'keyword': kw.get('keyword') or kw.get('keywords'),
        'searches': kw.get('searches'),
        'purchaseRate': kw.get('purchaseRate'),
        'avgPrice': kw.get('avgPrice'),
        'supplyDemandRatio': kw.get('supplyDemandRatio'),
    })

output = {
    'stats': stats,
    'top_products': simplified,
    'top_keywords': top_kw,
}
print(json.dumps(output, ensure_ascii=False))
PYEOF
)

PROMPT=$(cat <<PROMPT
你是一位资深亚马逊跨境电商选品专家，请对以下卖家精灵市场数据进行深度选品分析。

## 分析对象
查询词：${QUERY}
市场：${MARKETPLACE}

## 市场数据
\`\`\`json
${DATA_SUMMARY}
\`\`\`

## 输出格式要求

请严格按以下格式输出，中英文双语，不要添加额外说明：

---
BLUE_OCEAN_INDEX: [蓝海指数 0-10，越高越蓝海，基于竞争集中度和进入门槛计算]
MARKET_SIZE_ZH: [市场体量评估：大/中/小]
MARKET_SIZE_EN: [large/medium/small]
COMPETITION_LEVEL_ZH: [竞争强度：激烈/中等/较低]
COMPETITION_LEVEL_EN: [fierce/moderate/low]
ENTRY_DIFFICULTY_ZH: [入场难度：高/中/低]
ENTRY_DIFFICULTY_EN: [high/medium/low]
---
RISK_1_ZH: [风险1，20字以内]
RISK_1_EN: [Risk 1, under 20 words]
RISK_2_ZH: [风险2，20字以内]
RISK_2_EN: [Risk 2, under 20 words]
RISK_3_ZH: [风险3，20字以内]
RISK_3_EN: [Risk 3, under 20 words]
---
OPPORTUNITY_1_ZH: [机会1，25字以内]
OPPORTUNITY_1_EN: [Opportunity 1, under 25 words]
OPPORTUNITY_1_TYPE: [价格空白/功能差异/细分人群/新兴需求/渠道机会]
OPPORTUNITY_2_ZH: [机会2，25字以内]
OPPORTUNITY_2_EN: [Opportunity 2, under 25 words]
OPPORTUNITY_2_TYPE: [类型]
OPPORTUNITY_3_ZH: [机会3，25字以内]
OPPORTUNITY_3_EN: [Opportunity 3, under 25 words]
OPPORTUNITY_3_TYPE: [类型]
---
STRATEGY_1_ZH: [切入策略1，50字以内]
STRATEGY_1_EN: [Entry strategy 1, under 50 words]
STRATEGY_2_ZH: [切入策略2，50字以内]
STRATEGY_2_EN: [Entry strategy 2, under 50 words]
STRATEGY_3_ZH: [切入策略3，50字以内]
STRATEGY_3_EN: [Entry strategy 3, under 50 words]
---
RECOMMEND_PRICE_MIN: [推荐定价区间最低，数字]
RECOMMEND_PRICE_MAX: [推荐定价区间最高，数字]
RECOMMEND_PRICE_REASON_ZH: [推荐理由，30字以内]
RECOMMEND_PRICE_REASON_EN: [Reason in English, under 30 words]
---
TOP_ASIN_1: [参考ASIN 1]
TOP_ASIN_1_REASON_ZH: [推荐理由，20字以内]
TOP_ASIN_2: [参考ASIN 2]
TOP_ASIN_2_REASON_ZH: [推荐理由，20字以内]
TOP_ASIN_3: [参考ASIN 3]
TOP_ASIN_3_REASON_ZH: [推荐理由，20字以内]
---
VERDICT_ZH: [最终选品结论，50字以内，明确说明是否值得入场]
VERDICT_EN: [Final verdict in English, under 50 words]
PROMPT
)

# 模型切换
ORIG_MODEL=""
if [[ -n "$MODEL_ARG" ]]; then
  RESOLVED_MODEL=$(resolve_model "$MODEL_ARG")
  echo "🤖 使用模型: $RESOLVED_MODEL" >&2
  ORIG_MODEL=$(openclaw models list --plain 2>/dev/null | head -1 || echo "")
  openclaw models set "$RESOLVED_MODEL" >/dev/null 2>&1 || {
    echo "⚠️  模型切换失败: $RESOLVED_MODEL，使用当前默认模型" >&2
    ORIG_MODEL=""
  }
fi

SESSION_ID="ss-$(date +%s)"
RESPONSE=$(openclaw agent --local --session-id "$SESSION_ID" -m "$PROMPT" --json 2>/dev/null)

# 恢复原始模型
if [[ -n "$ORIG_MODEL" ]]; then
  openclaw models set "$ORIG_MODEL" >/dev/null 2>&1 || true
fi

ANALYSIS=$(echo "$RESPONSE" | python3 -c "
import sys, json
r = json.load(sys.stdin)
payloads = r.get('payloads', [])
if payloads:
    print(payloads[0].get('text', ''))
else:
    print('ERROR: empty response')
" 2>/dev/null)

if [[ -z "$ANALYSIS" ]] || echo "$ANALYSIS" | grep -q "^ERROR:"; then
  echo "❌ OpenClaw 分析失败: $ANALYSIS" >&2
  exit 1
fi

# 读取统计数据用于渲染
STATS=$(python3 -c "
import json
with open('$DATA_FILE') as f:
    data = json.load(f)
stats = data.get('stats', {})
products = data.get('products', [])
print(json.dumps({'stats': stats, 'total': len(products)}))
" 2>/dev/null || echo '{"stats":{},"total":0}')

# 渲染报告（通过环境变量传递数据，避免 heredoc 注入问题）
ACTUAL_MODEL=""
if [[ -n "$MODEL_ARG" ]]; then
  ACTUAL_MODEL=$(resolve_model "$MODEL_ARG")
fi
export _SS_ANALYSIS="$ANALYSIS"
export _SS_STATS="$STATS"
export _SS_MODEL="$ACTUAL_MODEL"
REPORT=$(python3 - <<'PYEOF'
import re, json, os

raw = os.environ.get('_SS_ANALYSIS', '')
stats_raw = json.loads(os.environ.get('_SS_STATS', '{"stats":{},"total":0}'))
stats = stats_raw.get('stats', {})
total = stats_raw.get('total', 0)
model_used = os.environ.get('_SS_MODEL', '')

def get(key):
    m = re.search(rf'^{key}:\s*(.+)$', raw, re.MULTILINE)
    return m.group(1).strip() if m else '—'

def bar(value, max_val=10, width=16):
    try:
        n = float(value)
        filled = round(n / max_val * width)
        filled = min(filled, width)
        return '█' * filled + '░' * (width - filled)
    except:
        return '░' * width

def score_label(v):
    try:
        n = float(v)
        if n >= 7: return '🟢 优秀'
        if n >= 4: return '🟡 一般'
        return '🔴 困难'
    except:
        return ''

blue_ocean = get('BLUE_OCEAN_INDEX')
comp_zh = get('COMPETITION_LEVEL_ZH')
entry_zh = get('ENTRY_DIFFICULTY_ZH')
mkt_zh = get('MARKET_SIZE_ZH')

report = f"""
╔══════════════════════════════════════════════════════════════╗
║      卖家精灵选品报告 / SellerSprite Product Report         ║
║  关键词: $QUERY  |  市场: $MARKETPLACE  |  $TODAY          ║
╚══════════════════════════════════════════════════════════════╝

📊 市场概览 / Market Overview
──────────────────────────────────────
  产品数量  Products     {stats.get('total_products', total)} 条
  平均月销量 Avg Units   {stats.get('avg_units', 0):,} 件/月
  平均价格  Avg Price    \${stats.get('avg_price', 0):.2f}
  价格区间  Price Range  \${stats.get('min_price', 0):.2f} — \${stats.get('max_price', 0):.2f}
  平均评分数 Avg Ratings {stats.get('avg_ratings', 0):,}
  FBA 比例  FBA Ratio    {stats.get('fba_ratio', 0):.1f}%
  头部集中度 Top10 Conc  {stats.get('top10_concentration', 0):.1f}%

🌊 蓝海指数 / Blue Ocean Index
──────────────────────────────────────
  {bar(blue_ocean)}  {blue_ocean} / 10  {score_label(blue_ocean)}
  市场体量: {mkt_zh}   竞争强度: {comp_zh}   入场难度: {entry_zh}

"""

# 品牌集中度
top_brands = stats.get('top_brands', [])
if top_brands:
    report += "🏆 TOP 品牌分布 / Brand Distribution\n"
    report += "──────────────────────────────────────\n"
    for i, b in enumerate(top_brands[:5], 1):
        brand = b.get('brand', 'Unknown')
        units = b.get('units', 0)
        report += f"  {i}. {brand:<20} {units:>6,} 件/月\n"
    report += "\n"

report += """🔴 风险预警 / Risk Signals
══════════════════════════════════════════════
"""
for i in range(1, 4):
    zh = get(f'RISK_{i}_ZH')
    en = get(f'RISK_{i}_EN')
    if zh == '—': break
    report += f"{i}. {zh}\n   {en}\n\n"

report += """🟢 机会窗口 / Opportunity Windows
══════════════════════════════════════════════
"""
for i in range(1, 4):
    zh = get(f'OPPORTUNITY_{i}_ZH')
    en = get(f'OPPORTUNITY_{i}_EN')
    otype = get(f'OPPORTUNITY_{i}_TYPE')
    if zh == '—': break
    report += f"{i}. [{otype}] {zh}\n   {en}\n\n"

report += """🎯 推荐切入策略 / Entry Strategy
══════════════════════════════════════════════
"""
for i in range(1, 4):
    zh = get(f'STRATEGY_{i}_ZH')
    en = get(f'STRATEGY_{i}_EN')
    if zh == '—': break
    report += f"{i}. {zh}\n   {en}\n\n"

price_min = get('RECOMMEND_PRICE_MIN')
price_max = get('RECOMMEND_PRICE_MAX')
price_reason_zh = get('RECOMMEND_PRICE_REASON_ZH')
price_reason_en = get('RECOMMEND_PRICE_REASON_EN')
report += f"""💰 推荐定价区间 / Recommended Price Range
──────────────────────────────────────
  \${price_min} — \${price_max}
  {price_reason_zh}
  {price_reason_en}

"""

report += """📌 TOP 参考产品 / Reference Products
──────────────────────────────────────────────
"""
for i in range(1, 4):
    asin = get(f'TOP_ASIN_{i}')
    reason_zh = get(f'TOP_ASIN_{i}_REASON_ZH')
    if asin == '—': break
    report += f"  {asin}  {reason_zh}\n"

verdict_zh = get('VERDICT_ZH')
verdict_en = get('VERDICT_EN')
report += f"""
📋 选品结论 / Final Verdict
══════════════════════════════════════════════
  {verdict_zh}
  {verdict_en}

══════════════════════════════════════════════
  由卖家精灵选品 Skill 生成 | Powered by SellerSprite AI
  数据来源: 卖家精灵 open.sellersprite.com{"  AI 模型: " + model_used if model_used else ""}
══════════════════════════════════════════════
"""

print(report)
PYEOF
)
unset _SS_ANALYSIS _SS_STATS _SS_MODEL

echo "$REPORT"

if [[ -n "$OUTPUT_FILE" ]]; then
  echo "$REPORT" > "$OUTPUT_FILE"
  echo "" >&2
  echo "💾 报告已保存到: $OUTPUT_FILE" >&2
fi
