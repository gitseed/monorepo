# Fetch all available AWS regions from the current account and write them
# to ai-sandbox/sigv4/regions.json. The envoy.pkl config generator and the TLS cert
# both read this file at build time. Mainland China regions (cn-north-1,
# cn-northwest-1) are excluded — they require a separate account and
# connectivity that we don't have.

data "aws_regions" "available" {
  all_regions = true
}

locals {
  # Exclude mainland China regions — they use a separate partition
  # (aws-cn) with different credentials and endpoints.
  regions = [
    for r in data.aws_regions.available.names :
    r if !contains(["cn-north-1", "cn-northwest-1"], r)
  ]
}

resource "local_file" "regions" {
  filename        = "${path.module}/../regions.json"
  file_permission = "0644"
  content = jsonencode({
    regions = local.regions
  })
}
