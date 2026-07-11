locals {

  frontend_bucket_name = "${var.project_name}-${var.environment}-frontend"

  uploads_bucket_name = "${var.project_name}-${var.environment}-uploads"

  processed_bucket_name = "${var.project_name}-${var.environment}-processed"

}

resource "aws_s3_bucket" "uploads" {

  bucket = local.uploads_bucket_name

  tags = {
    Name        = local.uploads_bucket_name
    Environment = var.environment
    Project     = var.project_name
  }

}
resource "aws_s3_bucket" "frontend" {
  bucket = local.frontend_bucket_name

  tags = {
    Name        = local.frontend_bucket_name
    Environment = var.environment
    Project     = var.project_name
  }
}
resource "aws_s3_bucket" "processed" {
  bucket = local.processed_bucket_name

  tags = {
    Name        = local.processed_bucket_name
    Environment = var.environment
    Project     = var.project_name
  }
}
resource "aws_s3_bucket_versioning" "uploads" {

  bucket = aws_s3_bucket.uploads.id

  versioning_configuration {
    status = "Enabled"
  }

}

resource "aws_s3_bucket_versioning" "processed" {

  bucket = aws_s3_bucket.processed.id

  versioning_configuration {
    status = "Enabled"
  }

}

resource "aws_s3_bucket_versioning" "frontend" {

  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }

}
resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {

  bucket = aws_s3_bucket.uploads.id

  rule {

    apply_server_side_encryption_by_default {

      sse_algorithm = "AES256"

    }

  }

}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {

  bucket = aws_s3_bucket.frontend.id

  rule {

    apply_server_side_encryption_by_default {

      sse_algorithm = "AES256"

    }

  }

}
resource "aws_s3_bucket_server_side_encryption_configuration" "processed" {

  bucket = aws_s3_bucket.processed.id

  rule {

    apply_server_side_encryption_by_default {

      sse_algorithm = "AES256"

    }

  }

}
resource "aws_s3_bucket_public_access_block" "uploads" {

  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true

}

resource "aws_s3_bucket_public_access_block" "proccessed" {

  bucket = aws_s3_bucket.processed.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true

}

resource "aws_s3_bucket_public_access_block" "frontend" {

  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false

}

resource "aws_s3_bucket_website_configuration" "frontend" {

  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }

}

resource "aws_s3_bucket_policy" "frontend" {

  bucket = aws_s3_bucket.frontend.id

  # Must wait until the public access block allows public policies
  depends_on = [aws_s3_bucket_public_access_block.frontend]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })

}

resource "aws_iam_role" "lambda_role" {

  name = "${var.project_name}-${var.environment}-lambda-role"

  assume_role_policy = jsonencode({

    Version = "2012-10-17"

    Statement = [

      {

        Action = "sts:AssumeRole"

        Effect = "Allow"

        Principal = {

          Service = "lambda.amazonaws.com"

        }

      }

    ]

  })

}
resource "aws_iam_role_policy_attachment" "lambda_logs" {

  role = aws_iam_role.lambda_role.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

}
resource "aws_lambda_function" "upload" {

  function_name = "${var.project_name}-${var.environment}-upload"

  filename = data.archive_file.upload_zip.output_path

source_code_hash = data.archive_file.upload_zip.output_base64sha256

  role = aws_iam_role.lambda_role.arn

  handler = "handler.lambda_handler"

  runtime = "python3.12"

  timeout = 30
  environment {

  variables = {

    UPLOAD_BUCKET = aws_s3_bucket.uploads.bucket

  }

}

}
data "archive_file" "upload_zip" {

  type = "zip"

  source_dir = "lambda/upload"

  output_path = "build/upload.zip"

}
resource "aws_apigatewayv2_api" "image_api" {

  name = "${var.project_name}-${var.environment}"

  protocol_type = "HTTP"

  # Allow cross-origin requests from any origin during development.
  # Restrict allowed_origins to your deployed frontend URL in production.
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
    max_age       = 300
  }

}
resource "aws_lambda_permission" "upload_permission" {

  statement_id = "AllowAPIGatewayInvoke"

  action = "lambda:InvokeFunction"

  function_name = aws_lambda_function.upload.function_name

  principal = "apigateway.amazonaws.com"

}
resource "aws_apigatewayv2_integration" "upload_integration" {

  api_id = aws_apigatewayv2_api.image_api.id

  integration_type = "AWS_PROXY"

  integration_uri = aws_lambda_function.upload.invoke_arn

  payload_format_version = "2.0"

}
resource "aws_apigatewayv2_route" "upload_route" {

  api_id = aws_apigatewayv2_api.image_api.id

  route_key = "POST /upload"

  target = "integrations/${aws_apigatewayv2_integration.upload_integration.id}"

}
resource "aws_apigatewayv2_stage" "default" {

  api_id = aws_apigatewayv2_api.image_api.id

  name = "$default"

  auto_deploy = true

}
resource "aws_iam_policy" "upload_bucket_policy" {

  name = "${var.project_name}-${var.environment}-upload-policy"

  policy = jsonencode({

    Version = "2012-10-17"

   Statement = [

  {

    Effect = "Allow"

    Action = [

      "s3:PutObject"

    ]

    Resource = [

      "${aws_s3_bucket.uploads.arn}/*"

    ]

  },

  {

    Effect = "Allow"

    Action = [

      "s3:ListBucket"

    ]

    Resource = [

      aws_s3_bucket.uploads.arn

    ]

  }

]

  })

}
resource "aws_iam_role_policy_attachment" "upload_bucket_attachment" {

  role = aws_iam_role.lambda_role.name

  policy_arn = aws_iam_policy.upload_bucket_policy.arn

}
resource "aws_iam_policy" "process_bucket_policy" {

  name = "${var.project_name}-${var.environment}-process-policy"

  policy = jsonencode({

    Version = "2012-10-17"

    Statement = [

      {

        Effect = "Allow"

        Action = [
          "s3:GetObject"
        ]

        Resource = [
          "${aws_s3_bucket.uploads.arn}/*"
        ]

      },

      {

        Effect = "Allow"

        Action = [
          "s3:PutObject"
        ]

        Resource = [
          "${aws_s3_bucket.processed.arn}/*"
        ]

      },

      {
        Effect = "Allow"

        Action = [
          "s3:ListBucket"
        ]

        Resource = [
          aws_s3_bucket.processed.arn
        ]
      },

      {
        Effect = "Allow"

        Action = [
          "s3:GetObject"
        ]

        Resource = [
          "${aws_s3_bucket.processed.arn}/*"
        ]
      }

    ]

  })

}
resource "aws_iam_role_policy_attachment" "process_bucket_attachment" {

  role = aws_iam_role.lambda_role.name

  policy_arn = aws_iam_policy.process_bucket_policy.arn

}

resource "aws_iam_policy" "gallery_bucket_policy" {

  name = "${var.project_name}-${var.environment}-gallery-policy"

  policy = jsonencode({

    Version = "2012-10-17"

    Statement = [

      {
        Effect = "Allow"

        Action = [
          "s3:ListBucket"
        ]

        Resource = [
          aws_s3_bucket.processed.arn
        ]
      },

      {
        Effect = "Allow"

        Action = [
          "s3:GetObject"
        ]

        Resource = [
          "${aws_s3_bucket.processed.arn}/*"
        ]
      }

    ]

  })

}

resource "aws_iam_role_policy_attachment" "gallery_bucket_attachment" {

  role = aws_iam_role.lambda_role.name

  policy_arn = aws_iam_policy.gallery_bucket_policy.arn

}
resource "aws_s3_bucket_cors_configuration" "uploads_cors" {
  bucket = aws_s3_bucket.uploads.id

  cors_rule {
    allowed_headers = ["*"]

    allowed_methods = [
      "PUT",
      "GET",
      "HEAD",
      "POST"
    ]

    # "*" covers file://, any localhost port, and any deployed domain.
    # TODO: Replace with your production frontend URL once deployed.
    allowed_origins = ["*"]

    expose_headers = ["ETag"]

    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_cors_configuration" "processed_cors" {
  bucket = aws_s3_bucket.processed.id

  cors_rule {
    allowed_headers = ["*"]

    allowed_methods = [
      "GET",
      "HEAD"
    ]

    # Allow any origin so the frontend (local or S3-hosted) can fetch images.
    # TODO: Replace with your production frontend URL once deployed.
    allowed_origins = ["*"]

    expose_headers = ["ETag", "Content-Disposition"]

    max_age_seconds = 3000
  }
}
data "archive_file" "process_zip" {

  type = "zip"

  source_dir = "lambda/process"

  output_path = "build/process.zip"

}
resource "aws_lambda_function" "process" {

  function_name = "${var.project_name}-${var.environment}-process"

  filename = data.archive_file.process_zip.output_path

  source_code_hash = data.archive_file.process_zip.output_base64sha256

  role = aws_iam_role.lambda_role.arn

  handler = "handler.lambda_handler"

  runtime = "python3.12"

  timeout = 60
  environment {

  variables = {

    UPLOAD_BUCKET = aws_s3_bucket.uploads.bucket

    PROCESSED_BUCKET = aws_s3_bucket.processed.bucket

  }

}

}
resource "aws_lambda_permission" "allow_s3" {

  statement_id = "AllowExecutionFromS3"

  action = "lambda:InvokeFunction"

  function_name = aws_lambda_function.process.function_name

  principal = "s3.amazonaws.com"

  source_arn = aws_s3_bucket.uploads.arn

}
resource "aws_s3_bucket_notification" "upload_trigger" {

  bucket = aws_s3_bucket.uploads.id

  lambda_function {

    lambda_function_arn = aws_lambda_function.process.arn

    events = [
      "s3:ObjectCreated:*"
    ]

  }

  depends_on = [
    aws_lambda_permission.allow_s3
  ]

}
data "archive_file" "gallery_zip" {

  type = "zip"

  source_dir = "lambda/gallery"

  output_path = "build/gallery.zip"

}
resource "aws_lambda_function" "gallery" {

  function_name = "${var.project_name}-${var.environment}-gallery"

  filename = data.archive_file.gallery_zip.output_path

  source_code_hash = data.archive_file.gallery_zip.output_base64sha256

  handler = "handler.lambda_handler"

  runtime = "python3.12"

  role = aws_iam_role.lambda_role.arn

  environment {

    variables = {

      PROCESSED_BUCKET = aws_s3_bucket.processed.bucket

    }

  }

}

resource "aws_lambda_permission" "gallery_permission" {

  statement_id = "AllowAPIGatewayInvokeGallery"

  action = "lambda:InvokeFunction"

  function_name = aws_lambda_function.gallery.function_name

  principal = "apigateway.amazonaws.com"

}

resource "aws_apigatewayv2_integration" "gallery_integration" {

  api_id = aws_apigatewayv2_api.image_api.id

  integration_type = "AWS_PROXY"

  integration_uri = aws_lambda_function.gallery.invoke_arn

  payload_format_version = "2.0"

}

resource "aws_apigatewayv2_route" "gallery_route" {

  api_id = aws_apigatewayv2_api.image_api.id

  route_key = "GET /gallery"

  target = "integrations/${aws_apigatewayv2_integration.gallery_integration.id}"

}