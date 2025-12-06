# 検証シナリオ: インラインルールと外部ルールの競合

## 目的
セキュリティグループのインラインルール（`ingress`/`egress`ブロック）と外部リソース（`aws_security_group_rule`、`aws_vpc_security_group_ingress_rule`）を混在させた場合の動作を確認する。

## 検証パターン

### パターン1: インライン + aws_security_group_rule
```hcl
resource "aws_security_group" "pattern1_sg" {
  name        = "pattern1-inline-and-sg-rule"
  description = "Testing inline ingress + aws_security_group_rule"
  vpc_id      = aws_vpc.test_vpc.id

  # インラインでSSHルールを定義
  ingress {
    description = "SSH (inline rule)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "pattern1-sg"
  }
}

# 外部リソースでHTTPルールを追加 → 競合の可能性
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

### パターン2: インライン + aws_vpc_security_group_ingress_rule
```hcl
resource "aws_security_group" "pattern2_sg" {
  name        = "pattern2-inline-and-vpc-sg-rule"
  description = "Testing inline ingress + aws_vpc_security_group_ingress_rule"
  vpc_id      = aws_vpc.test_vpc.id

  # インラインでSSHルールを定義
  ingress {
    description = "SSH (inline rule)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "pattern2-sg"
  }
}

# 外部リソースでHTTPSルールを追加 → 競合の可能性
resource "aws_vpc_security_group_ingress_rule" "pattern2_https" {
  security_group_id = aws_security_group.pattern2_sg.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "HTTPS (using aws_vpc_security_group_ingress_rule)"
}
```

### パターン3: インライン + 両方の外部リソース（最大競合）
```hcl
resource "aws_security_group" "pattern3_sg" {
  name        = "pattern3-inline-and-both-rules"
  description = "Testing inline ingress + both external rule types"
  vpc_id      = aws_vpc.test_vpc.id

  # インラインでSSHルールを定義
  ingress {
    description = "SSH (inline rule)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "pattern3-sg"
  }
}

# aws_security_group_ruleでHTTPルールを追加
resource "aws_security_group_rule" "pattern3_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.pattern3_sg.id
  description       = "HTTP (using aws_security_group_rule)"
}

# aws_vpc_security_group_ingress_ruleでHTTPSルールを追加
resource "aws_vpc_security_group_ingress_rule" "pattern3_https" {
  security_group_id = aws_security_group.pattern3_sg.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "HTTPS (using aws_vpc_security_group_ingress_rule)"
}
```

## 検証手順

### ステップ1: 現在のリソースをクリーンアップ
```bash
terraform destroy
```

### ステップ2: 新しい検証用コードに置き換え
上記3パターンを含む`main_conflict_test.tf`を作成

### ステップ3: Terraform Plan実行
```bash
terraform plan > terraform-plan-conflict-test.txt
```

**確認ポイント:**
- 警告メッセージの有無
- エラーメッセージの有無
- Terraformが競合を検出するか

### ステップ4: Terraform Apply実行
```bash
terraform apply
```

**確認ポイント:**
- リソース作成の成功/失敗
- AWS側でルールが正しく作成されるか
- 状態ファイル（tfstate）での管理状況

### ステップ5: 状態確認
```bash
# Terraform状態確認
terraform state list

# AWSコンソールまたはCLIでセキュリティグループルールを確認
aws ec2 describe-security-groups --group-ids <sg-id>
```

### ステップ6: 再度Planを実行（Drift検出）
```bash
terraform plan
```

**確認ポイント:**
- 差分が表示されるか
- Terraformが状態の不一致を検出するか

## 期待される結果

### Terraform公式ドキュメントによれば:

> **Warning**: Do not use `ingress` and `egress` blocks with `aws_security_group_rule` resources or `aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule` resources. Doing so will cause conflicts and produce inconsistent behavior.

### 予想される挙動:
1. **Plan段階**: 警告が表示される可能性（または表示されない可能性）
2. **Apply段階**: 成功する可能性が高いが、状態管理に問題が発生
3. **Refresh/再Apply時**: ルールの競合により、意図しない変更や削除が発生する可能性

## この検証で明らかになること

1. Terraformがどの段階で警告/エラーを出すか
2. 実際にリソースが作成できるか
3. 作成後、`terraform plan`を再度実行したときに差分が出るか（drift検出）
4. どのようなエラーメッセージが表示されるか
5. インラインルールと外部ルールの混在による実際の問題点

## 参考リンク

- [AWS Provider - aws_security_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group)
- [AWS Provider - aws_security_group_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule)
- [AWS Provider - aws_vpc_security_group_ingress_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule)
