resource "aws_iam_role" "update_retailer_inventory_handler_role" {
  name = "${var.environment_name}-${var.update_retailer_inventory_handler_name}-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "update_retailer_inventory_handler_policy" {
  name = "${var.environment_name}-${var.update_retailer_inventory_handler_name}-policy"
  role = aws_iam_role.update_retailer_inventory_handler_role.id

  policy = <<EOF
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Action": [
				"sqs:*"
			],
			"Effect": "Allow",
			"Resource": "*"
		}
	]
}
EOF
}

resource "aws_sqs_queue" "failure_update_retailer_inventory_sqs" {
  name = "${var.environment_name}-failure-${var.update_retailer_inventory_sqs_name}"
  tags = {
    Environment = var.environment_name
  }
}

resource "aws_sqs_queue" "update_retailer_inventory_sqs" {
  name = "${var.environment_name}-${var.update_retailer_inventory_sqs_name}"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.failure_update_retailer_inventory_sqs.arn,
    maxReceiveCount     = 3
  })
  tags = {
    Environment = var.environment_name
  }
}

data "archive_file" "update_retailer_inventory_handler" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/update_retailer_inventory_handler"
  output_path = "${path.module}/../../lambdas/update_retailer_inventory_handler.zip"
}

resource "aws_lambda_function" "update_retailer_inventory_handler" {
  filename                       = "${path.module}/../../lambdas/update_retailer_inventory_handler.zip"
  function_name                  = "${var.environment_name}_${var.update_retailer_inventory_handler_name}"
  role                           = aws_iam_role.update_retailer_inventory_handler_role.arn
  handler                        = "main.lambda_handler"
  runtime                        = "python3.9"
  source_code_hash = data.archive_file.update_retailer_inventory_handler.output_base64sha256

  environment {
    variables = {
      UPDATE_INDIVIDUAL_RETAILER_INVENTORY_SQS_NAME = "${var.environment_name}-${var.update_individual_retailer_inventory_sqs_name}"
      API_HOST = var.api_host
      LAMBDA_SECRET = var.lambda_secret
    }
  }
}

resource "aws_lambda_event_source_mapping" "update_retailer_inventory_handler_mapping" {
  event_source_arn = aws_sqs_queue.update_retailer_inventory_sqs.arn
  enabled          = true
  function_name    = aws_lambda_function.update_retailer_inventory_handler.arn
  batch_size       = 1
}

# Cloudwatch Log
resource "aws_cloudwatch_log_group" "update_retailer_inventory_handler" {
  name              = "/aws/lambda/${var.environment_name}_${var.update_retailer_inventory_handler_name}"
  retention_in_days = 14
}

resource "aws_iam_policy" "update_retailer_inventory_handler_logging_policy" {
  name        = "${var.environment_name}-LoggingPolicy-${var.update_retailer_inventory_handler_name}"
  path        = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.update_retailer_inventory_handler_role.name
  policy_arn = aws_iam_policy.update_retailer_inventory_handler_logging_policy.arn
}
