# This bucket can contain secrets so we shouldn't give any AI agents read access.
# The very same bucket that tofu is reading state from!
resource "cloudflare_r2_bucket" "sensitive_state" {
  account_id    = local.cf_account_id
  name          = "tofu-sensitive"
  storage_class = "Standard"
}

# This bucket is readable by the agent, to enable it to tofu plan.
# Therefore it should NOT have secrets.
resource "cloudflare_r2_bucket" "regular_state" {
  account_id    = local.cf_account_id
  name          = "tofu"
  storage_class = "Standard"
}
