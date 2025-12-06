# パターン1検証結果: インライン + aws_security_group_rule

## 検証目的

`aws_security_group`のインラインルール（`ingress`ブロック）と外部リソース（`aws_security_group_rule`）を混在させた場合の動作を検証する。

## 検証構成

### リソース構成

```hcl
# セキュリティグループ（インラインSSHルール付き）
resource "aws_security_group" "pattern1_sg" {
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

# 外部リソースでHTTPルールを追加
resource "aws_security_group_rule" "pattern1_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.pattern1_sg.id
  description       = "HTTP (using aws_security_group_rule)"
}
```

### 作成されたリソース

- **VPC**: `vpc-0218366c7c30575ef` (10.1.0.0/16)
- **Security Group**: `sg-0b4eaa235eef61631` (pattern1-inline-and-sg-rule)

## 検証手順と結果

### ステップ1: ベースリソース作成

インラインSSHルール付きのセキュリティグループを作成。

**結果**: ✅ 成功

```
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

### ステップ2: Terraform Plan（外部リソース追加前）

外部リソース`aws_security_group_rule.pattern1_http`を有効化してplanを実行。

**結果**: ✅ 警告・エラーなし

```
Plan: 1 to add, 0 to change, 0 to destroy.
```

**重要**: Plan段階では競合の警告は表示されない。

### ステップ3: Terraform Apply（外部リソース追加）

HTTPルールを外部リソースとして追加。

**結果**: ✅ 成功

```
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

- リソース作成成功: `sgrule-1223500833`
- エラーなし

### ステップ4: AWS上の状態確認

Security Group `sg-0b4eaa235eef61631` のIngressルール:

```json
[
  {
    "IpProtocol": "tcp",
    "FromPort": 80,
    "ToPort": 80,
    "Description": "HTTP (using aws_security_group_rule)",
    "CidrIp": "0.0.0.0/0"
  },
  {
    "IpProtocol": "tcp",
    "FromPort": 22,
    "ToPort": 22,
    "Description": "SSH (inline rule)",
    "CidrIp": "0.0.0.0/0"
  }
]
```

✅ AWS上では両方のルールが正常に作成されている。

### ステップ5: Drift検出（再Plan実行）

リソース作成後、再度`terraform plan`を実行。

**結果**: ⚠️ **競合検出！**

```
Plan: 0 to add, 1 to change, 0 to destroy.

  # aws_security_group.pattern1_sg will be updated in-place
  ~ resource "aws_security_group" "pattern1_sg" {
      ~ ingress = [
        - {
            - description = "HTTP (using aws_security_group_rule)"
            - from_port   = 80
            - to_port     = 80
            - protocol    = "tcp"
            - cidr_blocks = ["0.0.0.0/0"]
            ...
          },
          # (1 unchanged element hidden)
        ]
    }
```

Terraformが`pattern1_sg`を**更新しようとしている** - HTTPルールを削除しようとしている。

## 🚨 問題の本質

### 競合の仕組み

1. **外部リソース追加時**
   - `aws_security_group_rule`でHTTPルール作成
   - AWS APIでセキュリティグループにルール追加成功

2. **Terraform Stateの認識**
   - `pattern1_sg`の`ingress`属性にはSSHルールのみ記録
   - HTTPルールは`aws_security_group_rule`リソースとして別管理

3. **次回Plan時の動作**
   - Terraformが`pattern1_sg`の状態をrefresh
   - AWS上にHTTPルール（Port 80）が存在することを検出
   - しかし`pattern1_sg`の定義には含まれていない
   - Terraformは「予期しないルール」と判断
   - **削除しようとする**

### 予想される無限ループ

もし再度`terraform apply`を実行すると:

1. TerraformがHTTPルールを削除
2. しかし`aws_security_group_rule.pattern1_http`は存在
3. 次の`terraform plan`で再度HTTPルールを追加
4. 次の`terraform apply`で追加
5. その次の`terraform plan`でまた削除を試みる
6. **無限ループ**

## 検証結果サマリー

### ✅ 成功した点

- Plan段階でエラー・警告なし
- Apply段階でエラーなし
- AWS上でルールは正常に作成される

### ⚠️ 問題点

- **Drift（状態の不整合）が発生**
- 次回のPlanで意図しない変更が検出される
- インラインルールと外部リソースの混在は**管理不可能**

### 🔴 Terraform公式警告の妥当性

> **Warning**: Do not use `ingress` and `egress` blocks with `aws_security_group_rule` resources.

この警告は**完全に正しい**:
- 技術的には作成可能
- しかし状態管理が破綻する
- 継続的な運用は不可能

## 結論

### 重要な発見

1. **Plan/Apply段階では警告がない** - 問題は後から発生
2. **AWS上では正常動作** - AWSレベルでは問題なし
3. **Terraform State管理が破綻** - 状態の不整合が発生
4. **実運用では使用不可** - 無限ループの危険性

### 推奨事項

**絶対に混在させないこと:**
- インラインルール（`ingress`/`egress`ブロック）
- 外部リソース（`aws_security_group_rule`）

**どちらか一方を選択:**
- 小規模: インラインルール
- 大規模: 外部リソース（`aws_security_group_rule`または`aws_vpc_security_group_ingress_rule`）

## ログファイル

- `terraform-apply-conflict-base.log` - ベースリソース作成ログ
- `terraform-plan-pattern1.txt` - 外部リソース追加前のplan
- `terraform-apply-pattern1.log` - 外部リソース追加のapply
- `terraform-plan-pattern1-drift.txt` - Drift検出のplan

## 参考リソース

- [AWS Provider - aws_security_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group)
- [AWS Provider - aws_security_group_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule)
