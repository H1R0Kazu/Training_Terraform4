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

## 注意事項
- このコードは検証目的のため、本番環境では使用しないでください
- AWSの認証情報が適切に設定されている必要があります
- リソース作成により料金が発生する可能性があります
