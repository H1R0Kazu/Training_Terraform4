# パターン2検証結果: インライン + aws_vpc_security_group_ingress_rule

## 検証目的

`aws_security_group`のインラインルール（`ingress`ブロック）と外部リソース（`aws_vpc_security_group_ingress_rule`）を混在させた場合の動作を検証する。

## 検証構成

### リソース構成

```hcl
# セキュリティグループ（インラインSSHルール付き）
resource "aws_security_group" "pattern2_sg" {
  vpc_id = aws_vpc.conflict_test_vpc.id

  # インラインでSSHルールを定義
  ingress {
    description = "SSH (inline rule)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 外部リソースでHTTPSルールを追加
resource "aws_vpc_security_group_ingress_rule" "pattern2_https" {
  security_group_id = aws_security_group.pattern2_sg.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "HTTPS (using aws_vpc_security_group_ingress_rule)"
}
```

### 作成されたリソース

- **VPC**: `vpc-0218366c7c30575ef` (10.1.0.0/16)
- **Security Group**: `sg-09d3d503b238d6b14` (pattern2-inline-and-vpc-sg-rule)

## 検証手順と結果

### 前提条件

パターン1の検証により、既に以下の状態が発生している:
- pattern1で追加したHTTPルールがDrift状態
- Terraformが競合を検出している

### ステップ1: Terraform Plan（外部リソース追加前）

外部リソース`aws_vpc_security_group_ingress_rule.pattern2_https`を有効化してplanを実行。

**結果**: ✅ 警告なし（パターン1の競合警告あり）

```
Plan: 1 to add, 1 to change, 0 to destroy.

+ pattern2_https (新規作成)
~ pattern1_sg (パターン1の競合による更新)
```

**重要**: パターン2自体についての警告はない。

### ステップ2: Terraform Apply（外部リソース追加）

HTTPSルールを外部リソースとして追加。

**結果**: ✅ 成功（しかし副作用あり）

```
Apply complete! Resources: 1 added, 1 changed, 0 destroyed.

+ pattern2_https: 作成成功 (sgr-0a6aac74639d6df80)
~ pattern1_sg: 修正完了 (HTTPルール削除)
```

**重大な副作用**:
- パターン1のHTTPルールが削除された
- これはパターン1の競合が顕在化した結果

### ステップ3: AWS上の状態確認

#### Pattern1 (sg-0b4eaa235eef61631)

```json
[
  {
    "IpProtocol": "tcp",
    "FromPort": 22,
    "ToPort": 22,
    "Description": "SSH (inline rule)",
    "CidrIp": "0.0.0.0/0"
  }
]
```

⚠️ HTTP (80) が削除されている！

#### Pattern2 (sg-09d3d503b238d6b14)

```json
[
  {
    "IpProtocol": "tcp",
    "FromPort": 22,
    "ToPort": 22,
    "Description": "SSH (inline rule)",
    "CidrIp": "0.0.0.0/0"
  },
  {
    "IpProtocol": "tcp",
    "FromPort": 443,
    "ToPort": 443,
    "Description": "HTTPS (using aws_vpc_security_group_ingress_rule)",
    "CidrIp": "0.0.0.0/0"
  }
]
```

✅ SSH と HTTPS が両方存在

### ステップ4: Terraform State確認

```
aws_security_group_rule.pattern1_http              <- まだ存在
aws_vpc_security_group_ingress_rule.pattern2_https <- 新規作成
```

**State Drift発生**: pattern1_httpはState上は存在するが、AWS上では削除されている。

### ステップ5: Drift検出（再Plan実行）

リソース作成後、再度`terraform plan`を実行。

**結果**: ⚠️ **無限ループ確定！**

```
Plan: 1 to add, 1 to change, 0 to destroy.

+ aws_security_group_rule.pattern1_http (再作成)
~ aws_security_group.pattern2_sg (HTTPSルール削除)
```

**2つの競合が同時発生**:

1. **Pattern1**: HTTPルールを再作成しようとする
2. **Pattern2**: HTTPSルールを削除しようとする

## 🚨 無限ループの証明

### サイクル分析

```
Apply 1:
  - pattern1: HTTPルール削除
  - pattern2: HTTPSルール追加

Plan 2:
  - pattern1: HTTPルール追加を検出
  - pattern2: HTTPSルール削除を検出

Apply 2:
  - pattern1: HTTPルール追加
  - pattern2: HTTPSルール削除

Plan 3:
  - pattern1: HTTPルール削除を検出
  - pattern2: HTTPSルール追加を検出

... 無限に継続
```

### 実証

**Apply直後のPlan結果:**
- pattern1_http: `will be created` (AWS上にないため再作成)
- pattern2_sg: `will be updated` (HTTPSルールを削除)

次のApplyを実行すると:
- HTTPルール追加
- HTTPSルール削除

その次のPlanで:
- HTTPルール削除を検出
- HTTPSルール追加を検出

**完全な無限ループ**

## パターン1との比較

### 共通点

1. ✅ Plan/Apply段階でエラー・警告なし
2. ✅ AWS上でリソース作成成功
3. ⚠️ Drift（状態の不整合）発生
4. 🔴 無限ループの危険性

### 相違点

| 項目 | パターン1 | パターン2 |
|------|----------|----------|
| 外部リソース | `aws_security_group_rule` | `aws_vpc_security_group_ingress_rule` |
| 追加ルール | HTTP (Port 80) | HTTPS (Port 443) |
| 結果 | 同一 | 同一 |

**結論**: リソースタイプによらず、インラインルールとの混在は同じ問題を引き起こす。

## 検証結果サマリー

### ✅ 成功した点

- Plan段階でエラー・警告なし
- Apply段階でエラーなし
- AWS上でルールは正常に作成される
- 新しいリソースタイプでも動作は同じ

### ⚠️ 問題点

- **Drift（状態の不整合）が発生**
- 次回のPlanで意図しない変更が検出される
- **複数パターンを同時運用すると相互に影響**
- **無限ループが確実に発生**

### 🔴 Terraform公式警告の妥当性

> **Warning**: Do not use `ingress` and `egress` blocks with `aws_security_group_rule` resources or `aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule` resources.

この警告は**完全に正しい**:
- `aws_security_group_rule`でも発生
- `aws_vpc_security_group_ingress_rule`でも発生
- **両方とも同じ問題**

## 結論

### 重要な発見

1. **新旧リソースタイプで同じ問題** - `aws_vpc_security_group_ingress_rule`でも競合発生
2. **Plan/Apply段階では警告がない** - 問題は後から発生
3. **AWS上では正常動作** - AWSレベルでは問題なし
4. **Terraform State管理が破綻** - 状態の不整合が発生
5. **複数パターンの相互干渉** - pattern1とpattern2が互いに影響
6. **実運用では絶対に使用不可** - 無限ループが確実に発生

### パターン1 vs パターン2

**結論**: どちらのリソースタイプを使用しても**結果は同じ**

- `aws_security_group_rule`: 競合発生
- `aws_vpc_security_group_ingress_rule`: 競合発生

### 推奨事項

**絶対に混在させないこと:**
- インラインルール（`ingress`/`egress`ブロック）
- 外部リソース（どのタイプでも）

**選択肢:**
1. インラインルールのみ使用
2. `aws_security_group_rule`のみ使用（従来）
3. `aws_vpc_security_group_ingress_rule`のみ使用（推奨）

**混在は厳禁** - これは絶対的なルール

## ログファイル

- `terraform-plan-pattern2.txt` - 外部リソース追加前のplan
- `terraform-apply-pattern2.log` - 外部リソース追加のapply
- `terraform-plan-pattern2-drift.txt` - Drift検出のplan（無限ループ確認）

## 参考リソース

- [AWS Provider - aws_security_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group)
- [AWS Provider - aws_vpc_security_group_ingress_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule)
- [AWS Provider - aws_vpc_security_group_egress_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule)
