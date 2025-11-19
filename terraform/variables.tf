variable "region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-west-1"
}

variable "lambda_runtime" {
  description = "Lambda runtime to use for Python functions"
  type        = string
  default     = "python3.11"
}

variable "stage" {
  description = "API Gateway stage name"
  type        = string
  default     = "dev"
}
