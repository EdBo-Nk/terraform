output "s3_bucket_name" {
  value = aws_s3_bucket.email_storage_bucket.bucket
}

output "sqs_queue_url" {
  value = aws_sqs_queue.email_queue.id
}

output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  value       = aws_lb.email_api_alb.dns_name
}
output "grafana_url" {
  description = "URL to access Grafana"
  value       = "http://${aws_lb.email_api_alb.dns_name}:3000"
}

output "grafana_login" {
  description = "Grafana login information"
  value       = "Username: admin, Password: admin123"
}