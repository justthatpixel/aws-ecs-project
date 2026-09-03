variable "aws_region_current" {
  type    = string
  default = "eu-west-2"
}

variable "availability_zones" {
  type    = list(string)
  default = ["eu-west-2a", "eu-west-2b"]
}
