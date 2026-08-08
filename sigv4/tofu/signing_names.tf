data "github_rest_api" "head" {
  endpoint = "repos/aws/api-models-aws/commits/main"
}

data "github_rest_api" "models_tree" {
  endpoint = "repos/aws/api-models-aws/git/trees/${jsondecode(data.github_rest_api.head.body).sha}?recursive=1"
}

locals {
  model_blobs = {
    for entry in jsondecode(data.github_rest_api.models_tree.body).tree :
    regex("^models/([^/]+)/", entry.path)[0] => entry.sha
    if entry.type == "blob" && can(regex("^models/[^/]+/service/.+\\.json$", entry.path))
  }
}

# blob api instead of contents api: 25 models exceed the contents api 1MB limit
data "github_rest_api" "model" {
  for_each = local.model_blobs
  endpoint = "repos/aws/api-models-aws/git/blobs/${each.value}"
}

# regex instead of jsondecode: the models total 164MB, decoding them all is
# pointless when only the service shape's aws.auth#sigv4 trait is wanted.
# null means the service does not use sigv4 (e.g. codecatalyst is bearer auth)
locals {
  signing_names = {
    for service, model in data.github_rest_api.model :
    service => try(
      regex(
        "\"aws\\.auth#sigv4\": \\{\\s*\"name\": \"([^\"]+)\"",
        base64decode(replace(jsondecode(model.body).content, "\n", ""))
      )[0],
      null
    )
  }
}

resource "local_file" "signing_names" {
  filename        = "${path.module}/../signing_names.json"
  file_permission = "0644"
  content = jsonencode({
    commit   = jsondecode(data.github_rest_api.head.body).sha
    services = local.signing_names
  })
}
