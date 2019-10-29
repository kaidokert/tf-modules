provider "aws" {
  region = var.aws_region
}

terraform {
  backend "s3" {}
}

data "aws_s3_bucket" "target_bucket" {
  bucket = var.s3_bucket
}

data "aws_ssm_parameter" "gh_token" {
  name = var.gh_token_sm_param_name
}

resource "aws_s3_bucket" "build_bucket" {
  acl = "private"

  tags = {
    Name = "Static site build bucket"
    Site = "${var.site_name}"
  }
}

data "aws_iam_policy_document" "code_build_assume_policy" {
  statement {
    sid    = ""
    effect = "Allow"

    principals {
      identifiers = ["codebuild.amazonaws.com"]
      type        = "Service"
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "code_pipeline_assume_policy" {
  statement {
    sid    = ""
    effect = "Allow"

    principals {
      identifiers = ["codepipeline.amazonaws.com"]
      type        = "Service"
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "code_build_policy_document" {
  statement {
    sid     = ""
    effect  = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/*"
    ]
  }

  statement {
    sid     = ""
    effect  = "Allow"
    actions = ["s3:*"]
    resources = [
      "${aws_s3_bucket.target_bucket.arn}",
      "${aws_s3_bucket.target_bucket.arn}/*",
      "${aws_s3_bucket.build_bucket.arn}",
      "${aws_s3_bucket.build_bucket.arn}/*"
    ]
  }

  statement {
    sid     = ""
    effect  = "Allow"
    actions = ["cloudfront:CreateInvalidation"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "code_pipeline_policy_document" {
  statement {
    sid     = ""
    effect  = "Allow"
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.build_bucket.arn}",
      "${aws_s3_bucket.build_bucket.arn}/*"
    ]
  }

  statement {
    sid     = ""
    effect  = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning"
    ]
    resources = ["*"]
  }

  statement {
    sid     = ""
    effect  = "Allow"
    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "code_build_policy" {
  policy = "${data.aws_iam_policy_document.code_build_policy_document.json}"
}

resource "aws_iam_policy" "code_pipeline_policy" {
  policy = "${data.aws_iam_policy_document.code_pipeline_policy_document.json}"
}

resource "aws_iam_role" "code_build_role" {
  assume_role_policy = "${data.aws_iam_policy_document.code_build_assume_policy.json}"
}

resource "aws_iam_role" "code_pipeline_role" {
  assume_role_policy = "${data.aws_iam_policy_document.code_pipeline_assume_policy.json}"
}

resource "aws_iam_policy_attachment" "attach_cb_policy_to_role" {
  role        = "${aws_iam_role.code_build_role.name}"
  policy_arn  = "${aws_iam_policy.code_build_policy.arn}"
}

resource "aws_iam_policy_attachment" "attach_cp_policy_to_role" {
  role        = "${aws_iam_role.code_pipeline_role.name}"
  policy_arn  = "${aws_iam_policy.code_pipeline_policy.arn}"
}

resource "aws_codebuild_project" "codebuild_project" {
  name          = "basic-cicd-build-${var.site_name}-${var.cf_distribution}"
  description   = "build site ${var.site_name} for CF dist ${var.cf_distribution}"
  build_timeout = "${var.build_timeout}"
  service_role  = "${aws_iam_role.code_build_role.arn}"

  artifacts {
    type = "CODEPIPELINE"
  }

  cache {
    type = "NO_CACHE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:1.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "TARGET_BUCKET"
      value = "${var.s3_bucket}"
    }

    environment_variable {
      name  = "INVALIDATE"
      value = "${var.cf_invalidate}"
    }

    source {
      type = "CODEPIPELINE"
    }
  }
}