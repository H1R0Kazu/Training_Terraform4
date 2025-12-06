# VPC（セキュリティグループに必要）
resource "aws_vpc" "conflict_test_vpc" {
  cidr_block = "10.1.0.0/16"

  tags = {
    Name = "conflict-test-vpc"
  }
}

# =====================================
# パターン1: インライン + aws_security_group_rule
# =====================================
resource "aws_security_group" "pattern1_sg" {
  name        = "pattern1-inline-and-sg-rule"
  description = "Testing inline ingress + aws_security_group_rule"
  vpc_id      = aws_vpc.conflict_test_vpc.id

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

# =====================================
# パターン2: インライン + aws_vpc_security_group_ingress_rule
# =====================================
resource "aws_security_group" "pattern2_sg" {
  name        = "pattern2-inline-and-vpc-sg-rule"
  description = "Testing inline ingress + aws_vpc_security_group_ingress_rule"
  vpc_id      = aws_vpc.conflict_test_vpc.id

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

# =====================================
# パターン3: インライン + 両方の外部リソース（最大競合）
# =====================================
resource "aws_security_group" "pattern3_sg" {
  name        = "pattern3-inline-and-both-rules"
  description = "Testing inline ingress + both external rule types"
  vpc_id      = aws_vpc.conflict_test_vpc.id

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
