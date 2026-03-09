#!/usr/bin/env bash
# 卖家精灵 API 数据拉取脚本
# Usage: fetch.sh [--keyword KW] [--asin ASIN] [--marketplace US] [--month yyyyMM] [--size 50] [--output out.json]

set -euo pipefail

KEYWORD=""
ASIN=""
MARKETPLACE="US"
MONTH=""
SIZE=50
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keyword) KEYWORD="$2"; shift 2 ;;
    --asin) ASIN="$2"; shift 2 ;;
    --marketplace) MARKETPLACE="${2^^}"; shift 2 ;;
    --month) MONTH="$2"; shift 2 ;;
    --size) SIZE="$2"; shift 2 ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

API_BASE="https://api.sellersprite.com"
SECRET_KEY="${SELLERSPRITE_SECRET_KEY:-}"

if [[ -z "$SECRET_KEY" ]]; then
  echo "❌ 缺少 SELLERSPRITE_SECRET_KEY 环境变量" >&2
  exit 1
fi

# 通用 API 调用函数
api_post() {
  local endpoint="$1"
  local body="$2"

  curl -s -X POST \
    "${API_BASE}${endpoint}" \
    -H "secret-key: ${SECRET_KEY}" \
    -H "Content-Type: application/json;charset=utf-8" \
    -d "$body"
}

api_get() {
  local endpoint="$1"

  curl -s -X GET \
    "${API_BASE}${endpoint}" \
    -H "secret-key: ${SECRET_KEY}" \
    -H "Content-Type: application/json;charset=utf-8"
}

# 检查 API 余量
echo "🔑 检查 API 配额..." >&2
VISITS_RESP=$(api_get "/v1/visits" 2>/dev/null || echo '{"code":"ERROR"}')
VISITS_OK=$(echo "$VISITS_RESP" | python3 -c "
import sys, json
try:
    r = json.load(sys.stdin)
    print('ok' if r.get('code') == 'OK' else 'fail')
except:
    print('fail')
")

if [[ "$VISITS_OK" == "fail" ]]; then
  echo "⚠️  无法验证 API 配额（可能 Key 无效或网络问题）" >&2
fi

PRODUCTS_JSON="[]"
KEYWORD_DATA="{}"

# 1. 通过关键词拉取产品数据
if [[ -n "$KEYWORD" ]]; then
  echo "🔍 拉取产品数据（关键词: $KEYWORD, 市场: $MARKETPLACE）..." >&2

  # 构建 product/research 请求
  PRODUCT_BODY=$(python3 -c "
import json
body = {
    'marketplace': '$MARKETPLACE',
    'keyword': '$KEYWORD',
    'matchType': 2,
    'page': 1,
    'size': $SIZE,
    'order': {'field': 'units', 'desc': True}
}
$([ -n "$MONTH" ] && echo "body['month'] = '$MONTH'" || echo "pass")
print(json.dumps(body))
")

  PRODUCT_RESP=$(api_post "/v1/product/research" "$PRODUCT_BODY" 2>/dev/null || echo '{"code":"ERROR","data":{}}')

  PRODUCTS_JSON=$(echo "$PRODUCT_RESP" | python3 -c "
import sys, json
try:
    r = json.load(sys.stdin)
    if r.get('code') == 'OK':
        items = r.get('data', {}).get('items', [])
        print(json.dumps(items, ensure_ascii=False))
    else:
        print('[]')
        import sys; print(f'API错误: {r.get(\"message\", \"未知\")}', file=sys.stderr)
except Exception as e:
    print('[]')
    print(f'解析错误: {e}', file=sys.stderr)
" 2>/dev/null || echo "[]")

  P_COUNT=$(echo "$PRODUCTS_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
  echo "   ✓ 产品数据: $P_COUNT 条" >&2

  # 2. 关键词选品数据
  echo "🔍 拉取关键词市场数据..." >&2

  KW_BODY=$(python3 -c "
import json
body = {
    'marketplace': '$MARKETPLACE',
    'keywords': '$KEYWORD',
    'page': 1,
    'size': 20,
    'order': {'field': 'searches', 'desc': True}
}
$([ -n "$MONTH" ] && echo "body['month'] = '$MONTH'" || echo "pass")
print(json.dumps(body))
")

  KW_RESP=$(api_post "/v1/keyword-research" "$KW_BODY" 2>/dev/null || echo '{"code":"ERROR","data":{}}')

  KEYWORD_DATA=$(echo "$KW_RESP" | python3 -c "
import sys, json
try:
    r = json.load(sys.stdin)
    if r.get('code') == 'OK':
        data = r.get('data', {})
        items = data.get('items', [])
        print(json.dumps({'items': items, 'total': data.get('total', 0)}, ensure_ascii=False))
    else:
        print(json.dumps({'items': [], 'total': 0}))
except:
    print(json.dumps({'items': [], 'total': 0}))
" 2>/dev/null || echo '{"items":[],"total":0}')

  KW_COUNT=$(echo "$KEYWORD_DATA" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('items',[])))" 2>/dev/null || echo "0")
  echo "   ✓ 关键词数据: $KW_COUNT 条" >&2

# 3. 通过 ASIN 查竞品
elif [[ -n "$ASIN" ]]; then
  echo "🔍 查询 ASIN 竞品市场（$ASIN）..." >&2

  # ASIN 详情
  ASIN_RESP=$(api_get "/v1/asin/${MARKETPLACE}/${ASIN}" 2>/dev/null || echo '{"code":"ERROR"}')
  ASIN_DETAIL=$(echo "$ASIN_RESP" | python3 -c "
import sys, json
try:
    r = json.load(sys.stdin)
    print(json.dumps(r.get('data', {}), ensure_ascii=False))
except:
    print('{}')
" 2>/dev/null || echo "{}")

  # 获取竞品列表
  COMP_BODY=$(python3 -c "
import json
body = {
    'marketplace': '$MARKETPLACE',
    'asins': ['$ASIN'],
    'page': 1,
    'size': $SIZE,
    'order': {'field': 'units', 'desc': True}
}
$([ -n "$MONTH" ] && echo "body['month'] = '$MONTH'" || echo "pass")
print(json.dumps(body))
")

  COMP_RESP=$(api_post "/v1/product/competitor-lookup" "$COMP_BODY" 2>/dev/null || echo '{"code":"ERROR","data":{}}')

  PRODUCTS_JSON=$(echo "$COMP_RESP" | python3 -c "
import sys, json
try:
    r = json.load(sys.stdin)
    if r.get('code') == 'OK':
        items = r.get('data', {}).get('items', [])
        print(json.dumps(items, ensure_ascii=False))
    else:
        print('[]')
except:
    print('[]')
" 2>/dev/null || echo "[]")

  P_COUNT=$(echo "$PRODUCTS_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
  echo "   ✓ 竞品数据: $P_COUNT 条" >&2
fi

# 合并数据并计算统计指标
echo "📦 计算市场统计..." >&2

export _SS_FETCH_PRODUCTS="$PRODUCTS_JSON"
export _SS_FETCH_KW="$KEYWORD_DATA"
MERGED=$(python3 - <<'PYEOF'
import json, sys, os

products = json.loads(os.environ.get('_SS_FETCH_PRODUCTS', '[]'))
kw_data = json.loads(os.environ.get('_SS_FETCH_KW', '{}'))

# 计算市场统计
def safe_float(v):
    try: return float(v) if v is not None else 0.0
    except: return 0.0

def safe_int(v):
    try: return int(v) if v is not None else 0
    except: return 0

prices = [safe_float(p.get('price')) for p in products if p.get('price')]
units = [safe_int(p.get('units')) for p in products if p.get('units')]
revenues = [safe_float(p.get('revenue')) for p in products if p.get('revenue')]
ratings = [safe_int(p.get('ratings')) for p in products if p.get('ratings')]
rating_scores = [safe_float(p.get('rating')) for p in products if p.get('rating')]

# BSR 分布
bsr_list = [safe_int(p.get('bsr')) for p in products if p.get('bsr')]

# FBA 比例
fba_count = sum(1 for p in products if (p.get('fulfillment') or '').upper() in ['FBA', 'AMZ'])
fba_ratio = round(fba_count / len(products) * 100, 1) if products else 0

# Top 10 销量集中度
units_sorted = sorted(units, reverse=True)
top10_units = sum(units_sorted[:10])
total_units = sum(units_sorted)
concentration = round(top10_units / total_units * 100, 1) if total_units > 0 else 0

# 品牌集中度
brands = {}
for p in products:
    b = (p.get('brand') or 'Unknown').strip()
    if b:
        brands[b] = brands.get(b, 0) + safe_int(p.get('units', 0))
top_brands = sorted(brands.items(), key=lambda x: -x[1])[:5]

# 徽章分析
bs_count = sum(1 for p in products if p.get('badge', {}) and p['badge'].get('bestSeller'))
ac_count = sum(1 for p in products if p.get('badge', {}) and p['badge'].get('amazonChoice'))

# 蓝海指数计算（综合竞争强度、评分门槛、价格空间）
# 评分数越高竞争越激烈，concentration越高越难进入
avg_ratings = sum(ratings) / len(ratings) if ratings else 0
competition_score = min(concentration / 10, 10)  # 0-10
rating_barrier = min(avg_ratings / 5000, 1) * 5  # 0-5
blue_ocean = max(0, round(10 - competition_score * 0.5 - rating_barrier * 0.3, 1))

stats = {
    'total_products': len(products),
    'avg_price': round(sum(prices) / len(prices), 2) if prices else 0,
    'min_price': round(min(prices), 2) if prices else 0,
    'max_price': round(max(prices), 2) if prices else 0,
    'avg_units': round(sum(units) / len(units)) if units else 0,
    'total_units': total_units,
    'avg_revenue': round(sum(revenues) / len(revenues)) if revenues else 0,
    'avg_ratings': round(avg_ratings),
    'avg_rating_score': round(sum(rating_scores) / len(rating_scores), 2) if rating_scores else 0,
    'fba_ratio': fba_ratio,
    'top10_concentration': concentration,
    'top_brands': [{'brand': b, 'units': u} for b, u in top_brands],
    'bs_count': bs_count,
    'ac_count': ac_count,
    'blue_ocean_index': blue_ocean,
    'avg_bsr': round(sum(bsr_list) / len(bsr_list)) if bsr_list else 0,
}

# 精简 products 字段
simplified_products = []
for p in products[:50]:
    simplified_products.append({
        'asin': p.get('asin', ''),
        'title': (p.get('title') or '')[:100],
        'brand': p.get('brand', ''),
        'price': safe_float(p.get('price')),
        'units': safe_int(p.get('units')),
        'revenue': safe_float(p.get('revenue')),
        'ratings': safe_int(p.get('ratings')),
        'rating': safe_float(p.get('rating')),
        'bsr': safe_int(p.get('bsr')),
        'fulfillment': p.get('fulfillment', ''),
        'sellers': safe_int(p.get('sellers')),
        'badge': {
            'bestSeller': bool(p.get('badge', {}) and p['badge'].get('bestSeller')),
            'amazonChoice': bool(p.get('badge', {}) and p['badge'].get('amazonChoice')),
        } if p.get('badge') else {}
    })

output = {
    'query': {
        'keyword': '$KEYWORD',
        'asin': '$ASIN',
        'marketplace': '$MARKETPLACE',
        'month': '$MONTH',
    },
    'stats': stats,
    'products': simplified_products,
    'keywords': kw_data.get('items', [])[:20],
}

print(json.dumps(output, ensure_ascii=False, indent=2))
PYEOF
)
unset _SS_FETCH_PRODUCTS _SS_FETCH_KW

echo "✅ 数据整合完成" >&2

if [[ -n "$OUTPUT_FILE" ]]; then
  echo "$MERGED" > "$OUTPUT_FILE"
  echo "💾 数据已保存到: $OUTPUT_FILE" >&2
else
  echo "$MERGED"
fi
