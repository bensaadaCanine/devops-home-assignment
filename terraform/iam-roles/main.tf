module "iam-role" {
  for_each           = { for role in local.roles : role.role_name => role }
  source             = "../../terraform-modules/iam-role"
  role_name          = each.key
  oidc_provider_bool = each.value.oidc_provider_bool
  oidc_provider      = each.value.oidc_provider
  policies           = each.value.policies
}

