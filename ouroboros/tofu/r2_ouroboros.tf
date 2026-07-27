# Read-only R2 token for the lightning agent. The terraform state backend is
# S3-on-R2 (profile = "cloudflare"; see any tofu.tf). R2 S3-compatible creds
# are *derived* from a Cloudflare API token, not supplied separately:
#   Access Key ID      = token id
#   Secret Access Key  = SHA-256 of token value
# Source: https://developers.cloudflare.com/r2/api/tokens/
#         #get-s3-api-credentials-from-an-api-token
# This iteration only surfaces the derived creds into .env; a future
# iteration will write the `[cloudflare]` AWS profile to ~/.aws/credentials.
resource "cloudflare_account_token" "r2_ouroboros" {
  account_id = local.cf_account_id
  name       = "tofu-state-ouroboros"
  policies = [{
    effect = "allow"
    permission_groups = [{
      id = local.cf_perm_groups["com.cloudflare.edge.r2.bucket"]["Workers R2 Storage Bucket Item Write"]
    }]
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${local.cf_account_id}_${cloudflare_r2_bucket.regular_state.jurisdiction}_${cloudflare_r2_bucket.regular_state.name}"     = "*",
      "com.cloudflare.edge.r2.bucket.${local.cf_account_id}_${cloudflare_r2_bucket.sensitive_state.jurisdiction}_${cloudflare_r2_bucket.sensitive_state.name}" = "*",
    })
  }]
}

resource "infisical_secret" "r2_access_key_id" {
  name             = "R2_ACCESS_KEY_ID"
  value_wo         = cloudflare_account_token.r2_ouroboros.id
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.ouroboros.id
  folder_path      = "/"
}

resource "infisical_secret" "r2_secret_access_key" {
  name             = "R2_SECRET_ACCESS_KEY"
  value_wo         = sha256(cloudflare_account_token.r2_ouroboros.value)
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.ouroboros.id
  folder_path      = "/"
}
