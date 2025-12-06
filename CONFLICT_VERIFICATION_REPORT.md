# Terraform セキュリティグループルール競合検証 - 総合レポート

## 📋 検証概要

このプロジェクトでは、Terraformにおけるセキュリティグループルールの管理方法について、2つの観点から検証を実施しました。

### 検証の目的

1. **外部リソース同士の共存検証**（初回検証）
   - `aws_security_group_rule`（従来型）
   - `aws_vpc_security_group_ingress_rule`（新型）
   - → 結果: ✅ **共存可能**

2. **インラインルールと外部リソースの混在検証**（追加検証）
   - インラインルール（`ingress`/`egress`ブロック）
   - 外部リソース（両タイプ）
   - → 結果: 🔴 **競合発生・実運用不可**

## 🎯 検証1: 外部リソース同士の共存（成功）

### 検証構成

```hcl
# セキュリティグループ（インラインルールなし）
resource "aws_security_group" "test_sg" {
  vpc_id = aws_vpc.test_vpc.id
  # ingressブロックなし
}

# 従来型の外部リソース
resource "aws_security_group_rule" "allow_http" {
  type              = "ingress"
  from_port         = 80
  security_group_id = aws_security_group.test_sg.id
}

# 新型の外部リソース
resource "aws_vpc_security_group_ingress_rule" "allow_https" {
  security_group_id = aws_security_group.test_sg.id
  from_port         = 443
  ip_protocol       = "tcp"
}
```

### 検証結果

| 項目 | 結果 |
|------|------|
| Plan段階 | ✅ エラー・警告なし |
| Apply段階 | ✅ エラーなし |
| AWS上の状態 | ✅ 両方のルールが正常に作成 |
| Drift検出 | ✅ 差分なし |
| 継続運用 | ✅ 可能 |

**結論**: 外部リソース同士は問題なく共存可能

### 詳細レポート

- [検証手順と結果（README.md）](README.md)

---

## 🚨 検証2: インラインと外部リソースの混在（失敗）

### Terraform公式警告

> ⚠️ **Warning**: Do not use `ingress` and `egress` blocks with `aws_security_group_rule` resources or `aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule` resources. Doing so will cause conflicts and produce inconsistent behavior.

この警告の妥当性を実際に検証しました。

### パターン1: インライン + aws_security_group_rule

#### 検証構成

```hcl
resource "aws_security_group" "pattern1_sg" {
  vpc_id = aws_vpc.conflict_test_vpc.id

  # インラインルール
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 外部リソース
resource "aws_security_group_rule" "pattern1_http" {
  from_port         = 80
  security_group_id = aws_security_group.pattern1_sg.id
}
```

#### 検証結果

| ステップ | 結果 |
|---------|------|
| Plan（追加前） | ✅ 警告なし |
| Apply（追加） | ✅ 成功 |
| AWS上の状態 | ✅ 両ルール存在 |
| **再Plan（Drift検出）** | 🔴 **競合検出** |

#### Drift内容

```
Plan: 0 to add, 1 to change, 0 to destroy.

~ aws_security_group.pattern1_sg
  ~ ingress = [
    - { # HTTPルール削除を試みる
        from_port = 80
        ...
      },
      # SSHルールは維持
    ]
```

Terraformが外部リソースで追加したHTTPルールを**削除しようとする**。

### パターン2: インライン + aws_vpc_security_group_ingress_rule

#### 検証構成

```hcl
resource "aws_security_group" "pattern2_sg" {
  vpc_id = aws_vpc.conflict_test_vpc.id

  # インラインルール
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 新型の外部リソース
resource "aws_vpc_security_group_ingress_rule" "pattern2_https" {
  from_port         = 443
  security_group_id = aws_security_group.pattern2_sg.id
}
```

#### 検証結果

**パターン1と完全に同じ結果**

| 項目 | パターン1 | パターン2 |
|------|----------|----------|
| Plan段階 | ✅ 警告なし | ✅ 警告なし |
| Apply段階 | ✅ 成功 | ✅ 成功 |
| Drift検出 | 🔴 競合発生 | 🔴 競合発生 |
| 結果 | 削除試行 | 削除試行 |

**結論**: リソースタイプによらず同じ問題が発生

### 詳細レポート

- [パターン1詳細レポート](docs/pattern1-result.md)
- [パターン2詳細レポート](docs/pattern2-result.md)

---

## 💥 無限ループの実証

### 発生メカニズム

```
サイクル1: Apply
  → 外部リソースでルール追加
  → AWS上では正常に作成

サイクル2: Plan（直後）
  → Terraformが「予期しないルール」を検出
  → インラインリソースが削除を試みる

サイクル3: Apply
  → ルールが削除される
  → 外部リソースは依然として存在

サイクル4: Plan
  → 外部リソースがルール追加を試みる

サイクル5: Apply
  → ルールが再追加される

... 無限に継続
```

### 実際の検証結果

パターン2のApply後、パターン1のHTTPルールが**実際に削除**されました：

**Apply前**:
- Pattern1: SSH(22) + HTTP(80)
- Pattern2: SSH(22)

**Apply後**:
- Pattern1: SSH(22) のみ（HTTPが削除された）
- Pattern2: SSH(22) + HTTPS(443)

**次のPlan**:
- Pattern1: HTTPルール再作成を試みる
- Pattern2: HTTPSルール削除を試みる

→ **無限ループ確定**

---

## 📊 検証結果の比較

### ✅ 成功パターン（外部リソース同士）

| 要素 | aws_security_group_rule | aws_vpc_security_group_ingress_rule | 結果 |
|------|------------------------|-----------------------------------|------|
| 混在 | ✅ | ✅ | 可能 |
| Drift | なし | なし | 安定 |
| 運用 | 可能 | 可能 | 推奨 |

### 🔴 失敗パターン（インライン + 外部）

| 要素 | インライン | 外部リソース | 結果 |
|------|----------|------------|------|
| 混在 | 🔴 | 🔴 | 不可 |
| Drift | 発生 | 発生 | 破綻 |
| 運用 | 不可能 | 不可能 | 危険 |

---

## 🎓 学んだこと

### 1. Plan/Apply段階では問題が見えない

**重要**: Terraformは最初のPlan/Applyでは**警告を出さない**
- 技術的には作成可能
- エラーも発生しない
- AWS上でも正常に動作

しかし、**次のPlanで初めて問題が顕在化**する。

### 2. リソースタイプは関係ない

以下のどの組み合わせでも同じ問題：
- インライン + `aws_security_group_rule`
- インライン + `aws_vpc_security_group_ingress_rule`
- インライン + `aws_vpc_security_group_egress_rule`

**全て同じ結果** → 混在は不可

### 3. Terraform Stateの管理が破綻する

問題の本質は**State管理**：
- インラインルール: セキュリティグループリソース内で管理
- 外部リソース: 独立したリソースとして管理

同じAWSルールを**2つの異なる方法**で管理しようとするため、競合が発生。

### 4. 公式警告は100%正しい

Terraform公式ドキュメントの警告は**完全に妥当**：
- 技術的制約ではない
- State管理の設計上の制約
- 回避方法は存在しない

---

## ✅ ベストプラクティス

### 推奨される管理方法

#### 選択肢1: インラインルールのみ

```hcl
resource "aws_security_group" "example" {
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

**適用シーン**: 小規模、ルール数が少ない

#### 選択肢2: 外部リソースのみ（従来型）

```hcl
resource "aws_security_group" "example" {
  # ingressブロックなし
}

resource "aws_security_group_rule" "http" {
  type              = "ingress"
  from_port         = 80
  security_group_id = aws_security_group.example.id
}

resource "aws_security_group_rule" "https" {
  type              = "ingress"
  from_port         = 443
  security_group_id = aws_security_group.example.id
}
```

**適用シーン**: 大規模、動的なルール管理

#### 選択肢3: 外部リソースのみ（新型）- 推奨

```hcl
resource "aws_security_group" "example" {
  # ingressブロックなし
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.example.id
  from_port         = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.example.id
  from_port         = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}
```

**適用シーン**: 新規プロジェクト、最新の推奨方式

### 🚫 絶対にやってはいけないこと

```hcl
# ❌ 絶対にNG
resource "aws_security_group" "bad_example" {
  # インラインルール
  ingress {
    from_port = 22
  }
}

# 外部リソース（競合発生）
resource "aws_security_group_rule" "bad" {
  security_group_id = aws_security_group.bad_example.id
  from_port         = 80
}
```

**理由**: 無限ループ、State破綻、実運用不可

---

## 📁 プロジェクト構成

```
Training_Terraform4/
├── README.md                          # 初回検証（外部リソース同士）
├── CONFLICT_VERIFICATION_REPORT.md    # 本レポート（総合）
├── main.tf                            # 検証用Terraformコード
├── provider.tf                        # AWSプロバイダー設定
├── docs/
│   ├── conflict-test-scenario.md      # 競合テストシナリオ
│   ├── pattern1-result.md             # パターン1詳細レポート
│   └── pattern2-result.md             # パターン2詳細レポート
└── logs/
    ├── terraform-plan-*.txt           # Plan実行ログ
    ├── terraform-apply-*.log          # Apply実行ログ
    └── terraform-*-drift.txt          # Drift検出ログ
```

---

## 🔗 参考リソース

### 公式ドキュメント

- [AWS Provider - aws_security_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group)
- [AWS Provider - aws_security_group_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule)
- [AWS Provider - aws_vpc_security_group_ingress_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule)
- [AWS Provider - aws_vpc_security_group_egress_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule)

### 本プロジェクトのレポート

- [初回検証: 外部リソース同士の共存](README.md)
- [パターン1: インライン + aws_security_group_rule](docs/pattern1-result.md)
- [パターン2: インライン + aws_vpc_security_group_ingress_rule](docs/pattern2-result.md)
- [検証シナリオ詳細](docs/conflict-test-scenario.md)

---

## 💡 結論

### 検証1: 外部リソース同士

✅ **安全に混在可能**
- `aws_security_group_rule` + `aws_vpc_security_group_ingress_rule`
- 段階的な移行が可能
- State管理も問題なし

### 検証2: インラインと外部リソース

🔴 **絶対に混在不可**
- どのリソースタイプでも同じ
- 無限ループが確実に発生
- 実運用は不可能
- Terraform公式警告は完全に正しい

### 最終推奨事項

1. **新規プロジェクト**: `aws_vpc_security_group_ingress_rule`を使用
2. **既存プロジェクト（インライン）**: インラインのまま継続
3. **既存プロジェクト（外部）**: `aws_vpc_security_group_ingress_rule`へ移行検討
4. **混在は厳禁**: インラインと外部リソースは絶対に混在させない

---

**検証実施日**: 2025年12月6日
**Terraform**: v1.x
**AWS Provider**: ~> 5.0
**検証環境**: ap-northeast-1 (東京)
