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
