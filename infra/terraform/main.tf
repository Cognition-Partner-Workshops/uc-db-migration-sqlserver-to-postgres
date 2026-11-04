# Target-state sketch: Aurora PostgreSQL 18 cluster for the migrated estate.
# CI runs `terraform validate` only. Never plan or apply from this repo.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "aws_rds_cluster_parameter_group" "pc_insurance" {
  name   = "${var.name}-apg18"
  family = "aurora-postgresql18"

  parameter {
    name  = "timezone"
    value = "UTC"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  # Needed for AWS DMS CDC from SQL Server only when Aurora is also a CDC source;
  # kept off for a pure target.
  parameter {
    name         = "rds.logical_replication"
    value        = "0"
    apply_method = "pending-reboot"
  }
}

resource "aws_db_subnet_group" "pc_insurance" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

resource "aws_rds_cluster" "pc_insurance" {
  cluster_identifier              = var.name
  engine                          = "aurora-postgresql"
  engine_version                  = var.engine_version
  database_name                   = "pc_insurance"
  master_username                 = "pc_admin"
  manage_master_user_password     = true # credentials live in AWS Secrets Manager
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.pc_insurance.name
  db_subnet_group_name            = aws_db_subnet_group.pc_insurance.name
  vpc_security_group_ids          = var.security_group_ids
  storage_encrypted               = true
  backup_retention_period         = 7
  deletion_protection             = true
  copy_tags_to_snapshot           = true
  final_snapshot_identifier       = "${var.name}-final"
}

resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.name}-1"
  cluster_identifier = aws_rds_cluster.pc_insurance.id
  engine             = aws_rds_cluster.pc_insurance.engine
  engine_version     = aws_rds_cluster.pc_insurance.engine_version
  instance_class     = var.instance_class
}
