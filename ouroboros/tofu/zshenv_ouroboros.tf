# The very .zshenv file being used to authenticate to infisical!
# The machine identity isn't a secret. You can't get in without an established AWS authentication.
resource "local_sensitive_file" "zshenv" {
  content = templatefile("${path.module}/templates/zshenv.tftpl", {
    infisical_tofu_identity = infisical_identity.ouroboros.id
  })
  filename = pathexpand("~/.zshenv")
}
