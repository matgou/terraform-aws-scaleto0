variable "stackname" {
  description = "Name of stack"
  type        = string
}

variable "alb_listener_arn" {
  description = "ARN of alb to use for target group creation"
  type        = string
}

variable "rule_arn" {
  description = "ARN of rule to update with lambda"
}

variable "rule_priority" {
  description = "priority of rule"
}
variable "ecs_cluster_name" {
  description = "Name of cluster to update with greenlambda"
}
variable "ecs_service_name" {
  description = "Name of service to update with greenlambda"
}

variable "alb_arn_suffix" {
  description = "Suffix d'arn de l'alb"
}

variable "target_group_arn_suffix" {
  description = "Suffix d'arn du targetgroup qui est monitore"
}

