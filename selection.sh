#!/usr/bin/env bash
# 卖家精灵选品工具 - 主入口
# Usage: selection.sh [--keyword KEYWORD] [--asin ASIN] [--marketplace US] [--month yyyyMM] [--output file.md]

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_banner() {
  echo -e "${CYAN}"
  echo "  ███████╗███████╗██╗     ██╗     ███████╗██████╗ "
  echo "  ██╔════╝██╔════╝██║     ██║     ██╔════╝██╔══██╗"
  echo "  ███████╗█████╗  ██║     ██║     █████╗  ██████╔╝"
  echo "  ╚════██║██╔══╝  ██║     ██║     ██╔══╝  ██╔══██╗"
  echo "  ███████║███████╗███████╗███████╗███████╗██║  ██║"
  echo "  ╚══════╝╚══════╝╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝"
  echo -e "${NC}"
  echo "  卖家精灵 AI 选品助手 | SellerSprite Product Intelligence"
  echo "  ─────────────────────────────────────────────────────"
  echo ""
}

usage() {
  echo "Usage: selection.sh [options]"
  echo ""
  echo "Options:"
  echo "  --keyword KEYWORD    关键词（选品核心词）"
  echo "  --asin ASIN          通过 ASIN 分析竞品市场"
  echo "  --marketplace CODE   市场代码（默认: US）US/UK/DE/JP/CA/FR/IT/ES/MX/AU"
  echo "  --month yyyyMM       查询月份（默认: 最近月份）"
  echo "  --size N             拉取产品数量（默认: 50，max 100）"
  echo "  --model MODEL        AI 模型（默认使用 openclaw 当前配置）"
  echo "                       别名: claude/claude-opus/claude-haiku/gemini/gemini-flash"
  echo "                             gpt-4o/gpt-5/grok/deepseek/qwen/mistral"
  echo "                       完整ID: anthropic/claude-sonnet-4-6, openai/gpt-5 等"
  echo "  --output FILE        保存报告到文件"
  echo "  --help               显示帮助"
  echo ""
  echo "Examples:"
  echo "  selection.sh --keyword 'wireless earbuds'"
  echo "  selection.sh --keyword 'yoga mat' --marketplace UK --output report.md"
  echo "  selection.sh --asin B08N5WRWNW --marketplace US"
  exit 0
}

# 默认参数
KEYWORD=""
ASIN=""
MARKETPLACE="US"
MONTH=""
SIZE=50
OUTPUT_FILE=""
MODEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage ;;
    --keyword) KEYWORD="$2"; shift 2 ;;
    --asin) ASIN="$2"; shift 2 ;;
    --marketplace) MARKETPLACE=$(echo "$2" | tr '[:lower:]' '[:upper:]'); shift 2 ;;
    --month) MONTH="$2"; shift 2 ;;
    --size) SIZE="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    -*) echo -e "${RED}未知参数: $1${NC}" >&2; usage ;;
    *) KEYWORD="$1"; shift ;;
  esac
done

# 验证输入
if [[ -z "$KEYWORD" && -z "$ASIN" ]]; then
  echo -e "${RED}❌ 请提供 --keyword 或 --asin${NC}" >&2
  usage
fi

# 检查 API Key
if [[ -z "${SELLERSPRITE_SECRET_KEY:-}" ]]; then
  echo -e "${RED}❌ 未设置 SELLERSPRITE_SECRET_KEY${NC}" >&2
  echo "   请运行: export SELLERSPRITE_SECRET_KEY='your-secret-key'" >&2
  echo "   在 https://open.sellersprite.com 获取 API Key" >&2
  exit 1
fi

# 检查依赖
check_deps() {
  local missing=()

  if ! command -v curl &>/dev/null; then
    missing+=("curl")
  fi
  if ! command -v python3 &>/dev/null; then
    missing+=("python3")
  fi
  if ! command -v openclaw &>/dev/null; then
    missing+=("openclaw CLI（用于 AI 分析）")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${RED}❌ 缺少以下依赖:${NC}" >&2
    for dep in "${missing[@]}"; do
      echo "   • $dep" >&2
    done
    exit 1
  fi
}

print_banner
check_deps

# 显示任务信息
if [[ -n "$KEYWORD" ]]; then
  echo -e "${GREEN}▶ 选品分析 关键词: ${YELLOW}$KEYWORD${NC}"
else
  echo -e "${GREEN}▶ 竞品市场分析 ASIN: ${YELLOW}$ASIN${NC}"
fi
if [[ -n "$MODEL" ]]; then
  echo -e "  市场: $MARKETPLACE | 数据量: $SIZE 条 | 模型: $MODEL"
else
  echo -e "  市场: $MARKETPLACE | 数据量: $SIZE 条"
fi
echo ""

# 临时文件
TEMP_DATA=$(mktemp /tmp/ss_data_XXXXXX.json)
trap "rm -f $TEMP_DATA" EXIT

# 步骤1: 拉取卖家精灵数据
echo -e "${BLUE}[1/2] 拉取卖家精灵市场数据...${NC}"
bash "$SKILL_DIR/fetch.sh" \
  --keyword "$KEYWORD" \
  --asin "$ASIN" \
  --marketplace "$MARKETPLACE" \
  --month "$MONTH" \
  --size "$SIZE" \
  --output "$TEMP_DATA"

# 验证数据
PRODUCT_COUNT=$(python3 -c "
import json
data = json.load(open('$TEMP_DATA'))
products = data.get('products', [])
print(len(products))
" 2>/dev/null || echo "0")

if [[ "$PRODUCT_COUNT" -eq 0 ]]; then
  echo -e "${RED}❌ 未获取到产品数据，请检查:${NC}" >&2
  echo "   • SELLERSPRITE_SECRET_KEY 是否有效" >&2
  echo "   • 关键词/ASIN 是否正确" >&2
  echo "   • 市场代码是否正确（US/UK/DE/JP 等）" >&2
  exit 1
fi

echo -e "${GREEN}✓ 成功获取 $PRODUCT_COUNT 条产品数据${NC}"
echo ""

# 步骤2: AI 分析
echo -e "${BLUE}[2/2] AI 选品深度分析...${NC}"

ANALYZE_ARGS=("$TEMP_DATA" "${KEYWORD:-$ASIN}" "$MARKETPLACE")
[[ -n "$MODEL" ]] && ANALYZE_ARGS+=(--model "$MODEL")
[[ -n "$OUTPUT_FILE" ]] && ANALYZE_ARGS+=(--output "$OUTPUT_FILE")

bash "$SKILL_DIR/analyze.sh" "${ANALYZE_ARGS[@]}"

echo ""
echo -e "${GREEN}✅ 选品分析完成！${NC}"
