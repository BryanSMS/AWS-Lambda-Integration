data "aws_caller_identity" "current" {}
locals {
  name_prefix = "${var.project_name}-${var.environment}"
}
resource "aws_s3_bucket" "images" {
  bucket        = "${local.name_prefix}-images-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}
resource "aws_s3_bucket_public_access_block" "images" {
  bucket                  = aws_s3_bucket.images.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "images" {
  bucket     = aws_s3_bucket.images.id
  depends_on = [aws_s3_bucket_versioning.images]
  rule {
    id     = "expire-uploads"
    status = "Enabled"
    filter {
      prefix = "uploads/"
    }
    expiration {
      days = 30
    }
    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
  rule {
    id     = "expire-processed"
    status = "Enabled"
    filter {
      prefix = "processed/"
    }
    expiration {
      days = 90
    }
    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${local.name_prefix}-image-dlq"
  message_retention_seconds = 1209600 # 14 dias
}
resource "aws_sqs_queue" "main" {
  name                       = "${local.name_prefix}-image-queue"
  visibility_timeout_seconds = 360   # 6x el timeout de la crop-lambda (60 s)
  message_retention_seconds  = 86400 # 1 dia
  receive_wait_time_seconds  = 20    # long polling
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}
data "aws_iam_policy_document" "sqs_allow_s3" {
  statement {
    sid     = "AllowS3SendMessage"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    resources = [aws_sqs_queue.main.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.images.arn]
    }
  }
}
resource "aws_sqs_queue_policy" "main" {
  queue_url = aws_sqs_queue.main.id
  policy    = data.aws_iam_policy_document.sqs_allow_s3.json
}
resource "aws_s3_bucket_notification" "images" {
  bucket = aws_s3_bucket.images.id
  queue {
    queue_arn     = aws_sqs_queue.main.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "uploads/"
  }
  depends_on = [aws_sqs_queue_policy.main]
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "upload" {
  name               = "${local.name_prefix}-upload-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "upload_logs" {
  role       = aws_iam_role.upload.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
data "aws_iam_policy_document" "upload_s3" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.images.arn}/uploads/*"]
  }
}
resource "aws_iam_role_policy" "upload_s3" {
  name   = "s3-put-uploads"
  role   = aws_iam_role.upload.id
  policy = data.aws_iam_policy_document.upload_s3.json
}
resource "aws_iam_role" "crop" {
  name               = "${local.name_prefix}-crop-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "crop_logs" {
  role       = aws_iam_role.crop.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
data "aws_iam_policy_document" "crop_access" {
  statement {
    sid       = "ReadOriginals"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.images.arn}/uploads/*"]
  }
  statement {
    sid       = "WriteProcessed"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.images.arn}/processed/*"]
  }
  statement {
    sid = "ConsumeQueue"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility"
    ]
    resources = [aws_sqs_queue.main.arn]
  }
}
resource "aws_iam_role_policy" "crop_access" {
  name   = "crop-s3-and-sqs"
  role   = aws_iam_role.crop.id
  policy = data.aws_iam_policy_document.crop_access.json
}

data "archive_file" "upload" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/upload"
  output_path = "${path.module}/build/upload.zip"
}
resource "aws_cloudwatch_log_group" "upload" {
  name              = "/aws/lambda/${local.name_prefix}-upload"
  retention_in_days = 14
}
resource "aws_lambda_function" "upload" {
  function_name    = "${local.name_prefix}-upload"
  role             = aws_iam_role.upload.arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  memory_size      = 256
  timeout          = 30
  filename         = data.archive_file.upload.output_path
  source_code_hash = data.archive_file.upload.output_base64sha256
  environment {
    variables = {
      S3_BUCKET     = aws_s3_bucket.images.id
      UPLOAD_PREFIX = "uploads/"
    }
  }
  depends_on = [
    aws_cloudwatch_log_group.upload,
    aws_iam_role_policy_attachment.upload_logs,
  ]
}

data "archive_file" "crop" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/crop"
  output_path = "${path.module}/build/crop.zip"
}

resource "aws_cloudwatch_log_group" "crop" {
  name              = "/aws/lambda/${local.name_prefix}-crop"
  retention_in_days = 14
}

resource "aws_lambda_function" "crop" {
  function_name    = "${local.name_prefix}-crop"
  role             = aws_iam_role.crop.arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  memory_size      = 512
  timeout          = 60
  filename         = data.archive_file.crop.output_path
  source_code_hash = data.archive_file.crop.output_base64sha256

  environment {
    variables = {
      S3_BUCKET        = aws_s3_bucket.images.id
      UPLOAD_PREFIX    = "uploads/"
      PROCESSED_PREFIX = "processed/"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.crop,
    aws_iam_role_policy_attachment.crop_logs,
  ]
}

# Conecta la cola con la función
resource "aws_lambda_event_source_mapping" "crop_sqs" {
  event_source_arn        = aws_sqs_queue.main.arn
  function_name           = aws_lambda_function.crop.arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]

  depends_on = [aws_iam_role_policy.crop_access]
}