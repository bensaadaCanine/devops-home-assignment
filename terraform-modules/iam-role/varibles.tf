variable "policies" {
  description = "A list containing policies to attach to the role"
  type = list(object({
    name        = string
    description = optional(string)
    policy      = string
  }))
}

variable "role_name" {
  description = "role name"
  type        = string
  default     = ""
}

variable "oidc_provider_bool" {
  description = "Create OIDC trust relations"
  type        = bool
  default     = true
}
variable "oidc_provider" {
  description = "OIDC provider and the service account details"
  type = object({
    url                       = string
    account_id                = string
    service_account_name      = string
    service_account_namespace = string
  })
}
