# 使い方ガイド

このプロジェクトは、Terraformでのセキュリティグループルール管理における競合問題を検証し、インラインルールの検出を自動化するためのツールとドキュメントを提供します。

---

## 📚 このプロジェクトの内容

### 検証レポート

1. **[README.md](README.md)** - 初回検証: 外部リソース同士の共存
   - `aws_security_group_rule` と `aws_vpc_security_group_ingress_rule` の混在検証
   - 結果: ✅ 共存可能

2. **[CONFLICT_VERIFICATION_REPORT.md](CONFLICT_VERIFICATION_REPORT.md)** - 総合検証レポート
   - インラインルールと外部リソースの競合検証
   - 結果: 🔴 競合発生・実運用不可

### ツール

3. **[check-inline-rules.sh](check-inline-rules.sh)** - インラインルールチェッカー
   - Terraformコードを自動スキャン
   - インラインルールと外部リソースの混在を検出

### ガイド

4. **[HOW_TO_DETECT_INLINE_RULES.md](HOW_TO_DETECT_INLINE_RULES.md)** - 検出方法ガイド
   - インラインルールの判断方法（5つの方法）
   - CI/CD統合の例

---

## 🚀 クイックスタート

### 1. インラインルールチェックツールの使い方

#### ステップ1: 実行権限を付与

```bash
chmod +x check-inline-rules.sh
```

#### ステップ2: チェック実行

```bash
./check-inline-rules.sh
```

#### 出力例

**問題がある場合:**
```
🔴 インラインルール検出: aws_security_group.pattern1_sg
    - ingress ブロック: 1 個
    - egress ブロック: 0 個
    - ファイル: main.tf:13

⚠️  警告: インラインルールが検出されました

外部リソース（aws_security_group_rule など）と混在させないでください。
混在すると競合が発生し、無限ループに陥ります。
```

**問題がない場合:**
```
✅ 問題なし: インラインルールは検出されませんでした

すべてのルールが外部リソースで管理されています（推奨）
```

---

## 📖 検証コードの実行方法

### 前提条件

- Terraform 1.x以上
- AWS認証情報の設定
- AWS CLI（オプション）

### 基本的な実行手順

#### 1. 初期化

```bash
terraform init
```

#### 2. プランの確認

```bash
terraform plan
```

#### 3. リソースの作成

```bash
terraform apply
```

#### 4. 状態の確認

```bash
# Terraformで管理されているリソース一覧
terraform state list

# 特定のセキュリティグループの詳細
terraform state show aws_security_group.<name>
```

#### 5. リソースの削除

```bash
terraform destroy
```

---

## 🔍 検証パターンの切り替え

このプロジェクトには複数の検証パターンが含まれています。

### パターン1: 外部リソース同士（競合なし）

```bash
# main_basic.tf.bak を使用
cp main_basic.tf.bak main.tf
terraform plan
```

### パターン2: インラインルールと外部リソースの混在（競合あり）

```bash
# main_conflict_test.tf.bak を使用
cp main_conflict_test.tf.bak main.tf
terraform plan
```

現在の `main.tf` は競合検証パターンになっています。

---

## 🛡️ ベストプラクティス

### ✅ 推奨パターン

#### パターンA: 外部リソースのみ（新型 - 最も推奨）

```hcl
resource "aws_security_group" "example" {
  vpc_id = aws_vpc.main.id
  # ingress/egressブロックなし
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.example.id
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.example.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}
```

#### パターンB: 外部リソースのみ（従来型）

```hcl
resource "aws_security_group" "example" {
  vpc_id = aws_vpc.main.id
  # ingress/egressブロックなし
}

resource "aws_security_group_rule" "http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.example.id
}
```

#### パターンC: インラインルールのみ

```hcl
resource "aws_security_group" "example" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

**適用シーン**: 小規模、ルール数が少ない場合

### 🚫 禁止パターン

#### ❌ インラインと外部リソースの混在

```hcl
# 絶対にNG
resource "aws_security_group" "bad" {
  vpc_id = aws_vpc.main.id

  # インラインルール
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 外部リソース（これが競合する）
resource "aws_security_group_rule" "bad" {
  security_group_id = aws_security_group.bad.id
  from_port         = 80
  # ...
}
```

**理由**: 無限ループ、State破綻、実運用不可

---

## 🔧 トラブルシューティング

### Q1: `terraform plan` で意図しない差分が出る

**症状:**
```
~ aws_security_group.example
  ~ ingress = [
    - { from_port = 80 ... }  # 削除しようとする
  ]
```

**原因:** インラインルールと外部リソースの混在

**解決策:**
1. `./check-inline-rules.sh` を実行
2. 検出されたインラインルールを削除
3. すべて外部リソースで管理

### Q2: Apply後も差分が消えない

**症状:** 何度 `terraform apply` しても次の `plan` で差分が出る

**原因:** インラインルールと外部リソースの競合による無限ループ

**解決策:**
1. 現在のリソースを削除 (`terraform destroy`)
2. コードを修正（インラインまたは外部のいずれかに統一）
3. 再度作成 (`terraform apply`)

### Q3: どちらの管理方法を選ぶべき？

**新規プロジェクト:**
- `aws_vpc_security_group_ingress_rule`（新型）を使用

**既存プロジェクト（インライン使用中）:**
- 変更が小規模 → そのままインラインで継続
- 大規模リファクタリング → 外部リソースへ移行

**既存プロジェクト（外部リソース使用中）:**
- `aws_security_group_rule` → `aws_vpc_security_group_ingress_rule` への移行を検討

---

## 🔄 CI/CDへの統合

### GitHub Actions の例

```yaml
name: Terraform Validation

on:
  pull_request:
    paths:
      - '**.tf'

jobs:
  check-inline-rules:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Check for inline security group rules
        run: |
          chmod +x check-inline-rules.sh
          ./check-inline-rules.sh

      - name: Terraform Init
        run: terraform init

      - name: Terraform Validate
        run: terraform validate

      - name: Terraform Plan
        run: terraform plan
```

---

## 📊 ログとレポートの確認

### ログファイルの場所

```
logs/
├── terraform-plan-*.txt           # Plan実行ログ
├── terraform-apply-*.log          # Apply実行ログ
└── terraform-*-drift.txt          # Drift検出ログ
```

### レポートファイル

```
docs/
├── conflict-test-scenario.md      # 競合テストシナリオ
├── pattern1-result.md             # パターン1詳細レポート
└── pattern2-result.md             # パターン2詳細レポート
```

---

## 📚 詳細ドキュメント

| ドキュメント | 内容 |
|------------|------|
| [README.md](README.md) | 初回検証: 外部リソース同士の共存 |
| [CONFLICT_VERIFICATION_REPORT.md](CONFLICT_VERIFICATION_REPORT.md) | 総合検証レポート |
| [HOW_TO_DETECT_INLINE_RULES.md](HOW_TO_DETECT_INLINE_RULES.md) | インラインルール検出方法 |
| [conflict-test-scenario.md](docs/conflict-test-scenario.md) | 競合テストシナリオ |

---

## ⚠️ 注意事項

1. **本番環境では使用しない**
   - このコードは検証目的です
   - 本番環境での使用は推奨しません

2. **AWS料金**
   - リソース作成により料金が発生する可能性があります
   - 検証後は必ず `terraform destroy` でリソースを削除してください

3. **認証情報**
   - AWS認証情報を適切に設定してください
   - `.gitignore` で認証情報ファイルが除外されていることを確認してください

4. **State管理**
   - `.tfstate` ファイルには機密情報が含まれる可能性があります
   - リモートバックエンド（S3 + DynamoDBなど）の使用を検討してください

---

## 🤝 コントリビューション

このプロジェクトへの貢献を歓迎します！

1. Fork
2. Feature branch作成
3. `./check-inline-rules.sh` でチェック
4. Commit
5. Pull Request

---

## 📞 サポート

問題や質問がある場合は、GitHubのIssuesでお知らせください。

---

## 📄 ライセンス

このプロジェクトは検証・教育目的で作成されています。

---

**最終更新日**: 2025年12月6日
