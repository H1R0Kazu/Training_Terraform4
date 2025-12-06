#!/bin/bash

# インラインルールチェッカー
# セキュリティグループ内にingressまたはegressブロックがあるかを検出

echo "======================================"
echo "Terraform インラインルールチェッカー"
echo "======================================"
echo ""

# .tfファイルを検索
TF_FILES=$(find . -name "*.tf" -not -path "./.terraform/*")

if [ -z "$TF_FILES" ]; then
  echo "エラー: .tfファイルが見つかりません"
  exit 1
fi

echo "検索対象ファイル:"
echo "$TF_FILES"
echo ""
echo "======================================"
echo ""

FOUND_INLINE=0

for file in $TF_FILES; do
  echo "📄 チェック中: $file"
  echo ""

  # aws_security_groupリソースを含む行番号を取得
  SG_LINES=$(grep -n 'resource "aws_security_group"' "$file" | cut -d: -f1)

  if [ -z "$SG_LINES" ]; then
    echo "  ℹ️  aws_security_groupリソースなし"
    echo ""
    continue
  fi

  # 各セキュリティグループリソースをチェック
  while IFS= read -r line_num; do
    # リソース名を取得
    RESOURCE_NAME=$(sed -n "${line_num}p" "$file" | sed 's/.*"aws_security_group" "\([^"]*\)".*/\1/')

    # そのリソースブロック内でingressまたはegressブロックを検索
    # リソースの開始行から次のresourceまで（または最後まで）を検索範囲とする
    NEXT_RESOURCE=$(awk -v start="$line_num" 'NR>start && /^resource / {print NR; exit}' "$file")

    if [ -z "$NEXT_RESOURCE" ]; then
      # 次のリソースがない場合はファイルの最後まで
      SEARCH_RANGE="${line_num},\$"
    else
      SEARCH_RANGE="${line_num},$((NEXT_RESOURCE-1))"
    fi

    # ingressブロックをチェック
    INGRESS_COUNT=$(sed -n "${SEARCH_RANGE}p" "$file" | grep -c '^\s*ingress\s*{')

    # egressブロックをチェック
    EGRESS_COUNT=$(sed -n "${SEARCH_RANGE}p" "$file" | grep -c '^\s*egress\s*{')

    if [ "$INGRESS_COUNT" -gt 0 ] || [ "$EGRESS_COUNT" -gt 0 ]; then
      echo "  🔴 インラインルール検出: aws_security_group.$RESOURCE_NAME"
      echo "      - ingress ブロック: $INGRESS_COUNT 個"
      echo "      - egress ブロック: $EGRESS_COUNT 個"
      echo "      - ファイル: $file:$line_num"
      FOUND_INLINE=1
    else
      echo "  ✅ 外部管理: aws_security_group.$RESOURCE_NAME"
      echo "      - インラインルールなし（推奨）"
    fi
    echo ""
  done <<< "$SG_LINES"
done

echo "======================================"

# 外部リソースのチェック
echo ""
echo "📋 外部ルールリソースの確認:"
echo ""

SG_RULE_COUNT=$(grep -r 'resource "aws_security_group_rule"' $TF_FILES 2>/dev/null | wc -l | tr -d ' ')
VPC_SG_INGRESS_COUNT=$(grep -r 'resource "aws_vpc_security_group_ingress_rule"' $TF_FILES 2>/dev/null | wc -l | tr -d ' ')
VPC_SG_EGRESS_COUNT=$(grep -r 'resource "aws_vpc_security_group_egress_rule"' $TF_FILES 2>/dev/null | wc -l | tr -d ' ')

echo "  - aws_security_group_rule: $SG_RULE_COUNT 個"
echo "  - aws_vpc_security_group_ingress_rule: $VPC_SG_INGRESS_COUNT 個"
echo "  - aws_vpc_security_group_egress_rule: $VPC_SG_EGRESS_COUNT 個"

echo ""
echo "======================================"
echo ""

# 結果サマリー
if [ "$FOUND_INLINE" -eq 1 ]; then
  echo "⚠️  警告: インラインルールが検出されました"
  echo ""
  echo "外部リソース（aws_security_group_rule など）と混在させないでください。"
  echo "混在すると競合が発生し、無限ループに陥ります。"
  echo ""
  echo "推奨対応："
  echo "  1. すべてインラインルールに統一する"
  echo "  2. すべて外部リソースに移行する（推奨）"
  exit 1
else
  echo "✅ 問題なし: インラインルールは検出されませんでした"
  echo ""
  echo "すべてのルールが外部リソースで管理されています（推奨）"
  exit 0
fi
