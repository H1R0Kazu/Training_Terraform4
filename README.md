# Terraform AWS Security Group Rule Conflict Validation

## 概要
このリポジトリは、TerraformでAWSセキュリティグループのルール設定方法の違いと競合を検証するためのプロジェクトです。

## 検証内容

このプロジェクトでは、2つの観点から検証を実施しました：

### 検証1: 外部リソース同士の共存（本README）
以下の2つのルール設定方法を同時に使用した場合の動作を確認します:

1. `aws_security_group_rule` リソースでのルール追加（従来型）
2. `aws_vpc_security_group_ingress_rule` リソースでのルール追加（新型）

**結果**: ✅ **共存可能** - 競合なし、実運用可能

### 検証2: インラインルールと外部リソースの混在
インラインルール（`ingress`/`egress`ブロック）と外部リソースを混在させた場合の動作を検証しました。

**結果**: 🔴 **競合発生** - 無限ループ、実運用不可

詳細は [CONFLICT_VERIFICATION_REPORT.md](CONFLICT_VERIFICATION_REPORT.md) を参照してください。

## ファイル構成
```
Training_Terraform4/
├── README.md                          # 本ファイル（検証1の詳細）
├── CONFLICT_VERIFICATION_REPORT.md    # 総合検証レポート（検証1+2）
├── provider.tf                        # AWSプロバイダー設定
├── main.tf                            # セキュリティグループとルールの定義
├── docs/                              # 検証レポート
│   ├── conflict-test-scenario.md      # 検証2のシナリオ
│   ├── pattern1-result.md             # パターン1詳細レポート
│   └── pattern2-result.md             # パターン2詳細レポート
└── logs/                              # Terraform実行ログ
    ├── terraform-plan-*.txt
    └── terraform-apply-*.log
```

---

# 検証1: 外部リソース同士の共存

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

- VPC (vpc-REDACTED-02)
- Security Group (sg-REDACTED-01)

### ステップ2: aws_security_group_rule でHTTPルール追加

従来の `aws_security_group_rule` リソースを使用してHTTPルール（Port 80）を追加しました。

```bash
terraform apply
```

**追加されたリソース:**

- `aws_security_group_rule.allow_http` (sgr-REDACTED-03)

### ステップ3: aws_vpc_security_group_ingress_rule でHTTPSルール追加

新しい `aws_vpc_security_group_ingress_rule` リソースを使用してHTTPSルール（Port 443）を追加しました。

```bash
terraform apply
```

**追加されたリソース:**

- `aws_vpc_security_group_ingress_rule.allow_https` (sgr-REDACTED-02)

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

Security Group ID: `sg-REDACTED-01`

| Port | Protocol | Source | Description | 管理リソース |
|------|----------|--------|-------------|-------------|
| 80 | TCP | 0.0.0.0/0 | Allow HTTP from anywhere | `aws_security_group_rule` |
| 443 | TCP | 0.0.0.0/0 | Allow HTTPS from anywhere | `aws_vpc_security_group_ingress_rule` |

### ログファイル

検証1の実行ログは `logs/` ディレクトリに保存されています：

- `logs/terraform-plan.txt` - 初期plan（全リソース）
- `logs/terraform-plan-step2.txt` - ステップ2のplan
- `logs/terraform-plan-step3.txt` - ステップ3のplan
- `logs/terraform-apply-step3.log` - ステップ3の実行ログ

## 検証1の結論

### 重要な発見

1. **互換性あり**: Terraformは `aws_security_group_rule` と `aws_vpc_security_group_ingress_rule` の混在使用をサポートしています
2. **競合なし**: 同じセキュリティグループに対して両方のリソースタイプを使用してもエラーは発生しません
3. **移行可能**: 段階的に新しいリソースタイプへ移行することが可能です
4. **State管理**: 両リソースタイプは独立したリソースとして管理され、互いに干渉しません

### 推奨事項

- 新規プロジェクトでは `aws_vpc_security_group_ingress_rule` の使用を推奨
- 既存プロジェクトは段階的に移行可能
- 同じプロジェクト内で混在させることも技術的には可能だが、一貫性のため統一を推奨

---

# 総合的な結論

## ✅ 安全なパターン（検証1）

**外部リソース同士の共存**は問題なし：
- `aws_security_group_rule` + `aws_vpc_security_group_ingress_rule`
- 段階的な移行が可能
- Drift検出なし、実運用可能

## 🔴 危険なパターン（検証2）

**インラインルールと外部リソースの混在**は絶対に避けるべき：
- インライン（`ingress`/`egress`ブロック）+ 外部リソース（どちらのタイプでも）
- 無限ループが発生
- State管理が破綻
- 実運用不可能

詳細は [CONFLICT_VERIFICATION_REPORT.md](CONFLICT_VERIFICATION_REPORT.md) を参照してください。

---

## 参考リソース

### 公式ドキュメント

- [AWS Provider - aws_security_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group)
- [AWS Provider - aws_security_group_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule)
- [AWS Provider - aws_vpc_security_group_ingress_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule)
- [AWS Provider - aws_vpc_security_group_egress_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule)

### 本プロジェクトのレポート

- [総合検証レポート](CONFLICT_VERIFICATION_REPORT.md) - 両検証の統合レポート
- [パターン1詳細レポート](docs/pattern1-result.md) - インライン + aws_security_group_rule
- [パターン2詳細レポート](docs/pattern2-result.md) - インライン + aws_vpc_security_group_ingress_rule
- [検証シナリオ](docs/conflict-test-scenario.md) - 検証2のシナリオ詳細

---

## 注意事項

- このコードは検証目的のため、本番環境では使用しないでください
- AWSの認証情報が適切に設定されている必要があります
- リソース作成により料金が発生する可能性があります
- 検証2のリソース（pattern1_sg, pattern2_sg）は現在も残っている可能性があります

---

**検証実施日**: 2025年12月6日
**Terraform**: v1.x
**AWS Provider**: ~> 5.0
**検証環境**: ap-northeast-1 (東京)
