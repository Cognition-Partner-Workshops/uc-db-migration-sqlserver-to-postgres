output "cluster_endpoint" {
  value = aws_rds_cluster.pc_insurance.endpoint
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret holding the generated master credentials"
  value       = aws_rds_cluster.pc_insurance.master_user_secret[0].secret_arn
}
