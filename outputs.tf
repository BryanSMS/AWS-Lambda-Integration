output "account_id" {
  description = "Cuenta de AWS donde se despliega"
  value       = data.aws_caller_identity.current.account_id
}
output "bucket_name" {
  description = "Bucket de imagenes"
  value       = aws_s3_bucket.images.id
}
