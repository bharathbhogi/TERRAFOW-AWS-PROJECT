# To get rid of bucket policy error. After terraform apply and getting the error, run terraform apply again without destroying the resources.

provider "aws" {
  profile = "default"
  region = "ap-south-1"  # Change to your desired region
}

#Create Bucket with bucket name
resource "aws_s3_bucket" "static_website" {
  bucket = "route53.safeinfo.in" #Any name of the bucket
}

#Configure Bucket for static site hosting
resource "aws_s3_bucket_website_configuration" "static_website_config" {
  bucket = aws_s3_bucket.static_website.id
  
   index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

#Bucket ACL Configuration
resource "aws_s3_bucket_ownership_controls" "ownership" {
  bucket = aws_s3_bucket.static_website.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.static_website.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
resource "aws_s3_bucket_acl" "s3_acl" {
  depends_on = [
    aws_s3_bucket_ownership_controls.ownership,
    aws_s3_bucket_public_access_block.public_access,
  ]

  bucket = aws_s3_bucket.static_website.id
  acl    = "public-read"
}
  

#AWS Bucket Policy Configuration 
resource "aws_s3_bucket_policy" "allow_access_from_another_account" {
  bucket = aws_s3_bucket.static_website.id
  policy = data.aws_iam_policy_document.allow_access_from_another_account.json
}
#JSON Policy Configuration
data "aws_iam_policy_document" "allow_access_from_another_account" {
  statement {
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.static_website.arn,
      "${aws_s3_bucket.static_website.arn}/*",
    ]
  }
}

variable "files_to_upload" {
  type    = list(string)
  default = ["index.html", "error.html"]
}

#Upload the files
resource "aws_s3_object" "s3_objects" {
  for_each = toset(var.files_to_upload)

  bucket = aws_s3_bucket.static_website.id
  key    = each.value
  source = each.value  # Assuming files are in the same directory as your Terraform configuration
  content_type = "text/html"
}