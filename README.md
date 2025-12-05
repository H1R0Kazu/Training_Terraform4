# Terraform AWS Security Group Rule Conflict Validation

## 概要
このリポジトリは、TerraformでAWSセキュリティグループのルール設定方法の違いと競合を検証するためのプロジェクトです。

## 検証内容
以下の2つのルール設定方法を同時に使用した場合の動作を確認します:

1. `aws_security_group_rule` リソースでのルール追加
2. `aws_vpc_security_group_ingress_rule` リソースでのルール追加

## ファイル構成
- `provider.tf` - AWSプロバイダー設定
- `main.tf` - セキュリティグループとルールの定義

## 構成内容
- VPC: テスト用VPC (10.0.0.0/16)
- Security Group: test-security-group
  - Port 80 (HTTP): `aws_security_group_rule` で設定
  - Port 443 (HTTPS): `aws_vpc_security_group_ingress_rule` で設定

## 使用方法
```bash
# 初期化
terraform init

# プラン確認
terraform plan

# 適用
terraform apply

# 削除
terraform destroy
```

## 検証手順

### ステップ1: VPCとセキュリティグループの作成

まず、基本となるVPCとセキュリティグループを作成しました（ルールなし）。

```bash
terraform apply
```

**作成されたリソース:**

- VPC (vpc-032c236a15adbd5ae)
- Security Group (sg-04ad30f8c2f96a412)

### ステップ2: aws_security_group_rule でHTTPルール追加

従来の `aws_security_group_rule` リソースを使用してHTTPルール（Port 80）を追加しました。

```bash
terraform apply
```

**追加されたリソース:**

- `aws_security_group_rule.allow_http` (sgr-0d8305d6f30f3c8d0)

### ステップ3: aws_vpc_security_group_ingress_rule でHTTPSルール追加

新しい `aws_vpc_security_group_ingress_rule` リソースを使用してHTTPSルール（Port 443）を追加しました。

```bash
terraform apply
```

**追加されたリソース:**

- `aws_vpc_security_group_ingress_rule.allow_https` (sgr-0e53651a8302041d7)

## 検証結果

### ✅ 結果: 成功（競合なし）

2つの異なるリソースタイプを同じセキュリティグループに対して使用した結果：

1. **エラーなし**: すべてのステップでエラーは発生しませんでした
2. **正常に作成**: 両方のルールが正常にセキュリティグループに追加されました
3. **共存可能**: `aws_security_group_rule` と `aws_vpc_security_group_ingress_rule` は同じセキュリティグループで問題なく共存できます

### Terraform管理リソース

```text
aws_vpc.test_vpc
aws_security_group.test_sg
aws_security_group_rule.allow_http              (従来の方法)
aws_vpc_security_group_ingress_rule.allow_https (新しい方法)
```

### AWS上のセキュリティグループルール

Security Group ID: `sg-04ad30f8c2f96a412`

| Port | Protocol | Source | Description | 管理リソース |
|------|----------|--------|-------------|-------------|
| 80 | TCP | 0.0.0.0/0 | Allow HTTP from anywhere | `aws_security_group_rule` |
| 443 | TCP | 0.0.0.0/0 | Allow HTTPS from anywhere | `aws_vpc_security_group_ingress_rule` |

### ログファイル

- `terraform-plan.txt` - 初期plan（全リソース）
- `terraform-plan-step2.txt` - ステップ2のplan
- `terraform-plan-step3.txt` - ステップ3のplan
- `terraform-apply-step3.log` - ステップ3の実行ログ

## 結論

### 重要な発見

1. **互換性あり**: Terraformは `aws_security_group_rule` と `aws_vpc_security_group_ingress_rule` の混在使用をサポートしています
2. **競合なし**: 同じセキュリティグループに対して両方のリソースタイプを使用してもエラーは発生しません
3. **移行可能**: 段階的に新しいリソースタイプへ移行することが可能です

### 推奨事項

- 新規プロジェクトでは `aws_vpc_security_group_ingress_rule` の使用を推奨
- 既存プロジェクトは段階的に移行可能
- 同じプロジェクト内で混在させることも技術的には可能だが、一貫性のため統一を推奨

### 参考リソース

- [AWS Provider - aws_security_group_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule)
- [AWS Provider - aws_vpc_security_group_ingress_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule)

## 注意事項
- このコードは検証目的のため、本番環境では使用しないでください
- AWSの認証情報が適切に設定されている必要があります
- リソース作成により料金が発生する可能性があります
