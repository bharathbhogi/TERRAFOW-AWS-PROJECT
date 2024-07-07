provider "aws" {
  region = "ap-south-1"  # Change to your desired region

  default_tags {
    tags = {
      hashicorp-learn = "lambda-api-gateway"
    }
}
}

# Need S3 bucket to store Functions Data
#Create Bucket with bucket name
resource "aws_s3_bucket" "lambda_bucket" {
  bucket = "functions-bucket-terraform" #Any name of the bucket
}
#Set the Bucket ACL
resource "aws_s3_bucket_ownership_controls" "bucker_owner" {
  bucket = aws_s3_bucket.lambda_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}
resource "aws_s3_bucket_acl" "lamda_bucket_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.bucker_owner]

  bucket = aws_s3_bucket.lambda_bucket.id
  acl    = "private"
}

#Compress all the functions and push it to S3 bucket
#Compress all the functions
data "archive_file" "lambda_s3_data" {
  type = "zip"

  source_dir  = "${path.module}/handlers"
  output_path = "${path.module}/handlers.zip"
}
# Send all the functions to s3 bucket
resource "aws_s3_object" "lambda_s3" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "handlers.zip"
  source = data.archive_file.lambda_s3_data.output_path

  etag = filemd5(data.archive_file.lambda_s3_data.output_path)
}


#Create lambda function for allocating resources in AWS
resource "aws_lambda_function" "lambda_function" {
  function_name = "HelloWorld"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_s3.key

  runtime = "nodejs18.x"
  handler = "handler.handler"

  source_code_hash = data.archive_file.lambda_s3_data.output_base64sha256

  role = aws_iam_role.lambda_exec.arn
}

# Initiate cloudwatch logs to get logs
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name = "/aws/lambda/${aws_lambda_function.lambda_function.function_name}"

  retention_in_days = 30
}

#IAM Role Create to Execute Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "serverless_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

#Attach role to Lambda
resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#Output Function Name
output "function_name" {
  description = "Name of the Lambda function."

  value = aws_lambda_function.lambda_function.function_name
}

# Now setup API Gateway to execute the Lambda function through REST API
#Create API Gateway
resource "aws_apigatewayv2_api" "lambda_gateway_api" {
  name          = "serverless_lambda_gw"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda_gateway_stage" {
  api_id = aws_apigatewayv2_api.lambda_gateway_api.id

  name        = "serverless_lambda_stage"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.lambda_logs.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

#Integrate the API gateway with the lambda
resource "aws_apigatewayv2_integration" "lambda_gateway_integration" {
  api_id = aws_apigatewayv2_api.lambda_gateway_api.id

  integration_uri    = aws_lambda_function.lambda_function.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

# Add custom routes
resource "aws_apigatewayv2_route" "gateway_route" {
  api_id = aws_apigatewayv2_api.lambda_gateway_api.id

  route_key = "GET /hello"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_gateway_integration.id}"
}

resource "aws_cloudwatch_log_group" "api_gw_logs" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.lambda_gateway_api.name}"

  retention_in_days = 30
}

#Give permission to gateway to invoke lambda
resource "aws_lambda_permission" "api_gw_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda_gateway_api.execution_arn}/*/*"
}

#Print BASE URL to call API
output "base_url" {
  description = "Base URL for API Gateway stage."

  value = aws_apigatewayv2_stage.lambda_gateway_stage.invoke_url
}