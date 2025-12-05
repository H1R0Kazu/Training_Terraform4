# VPC（セキュリティグループに必要）
resource "aws_vpc" "test_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "test-vpc-for-sg-validation"
  }
}

# 1. セキュリティグループを作成
resource "aws_security_group" "test_sg" {
  name        = "test-security-group"
  description = "Security group for testing rule conflicts"
  vpc_id      = aws_vpc.test_vpc.id

  tags = {
    Name = "test-sg"
  }
}

# 2. aws_security_group_rule でルールを追加
resource "aws_security_group_rule" "allow_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.test_sg.id
  description       = "Allow HTTP from anywhere (using aws_security_group_rule)"
}

# 3. aws_vpc_security_group_ingress_rule でルールを追加
resource "aws_vpc_security_group_ingress_rule" "allow_https" {
  security_group_id = aws_security_group.test_sg.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow HTTPS from anywhere (using aws_vpc_security_group_ingress_rule)"
}
