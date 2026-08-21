locals {
  workspace = local.workspaces[tofu.workspace]

  contact_names = toset([
    for line in split("\n", file("${path.module}/../../allowed_callers.txt")) :
    trimspace(line) if trimspace(line) != ""
  ])

  workspaces = {
    veronica = {
      project_id = "untrusted-agent"
      region     = "us-central1"
      cloudflare_account_id = "287cae24e46a0aeed1dbc2942fc58dd7"
      voice_zone      = "veronica-agent.com"
      voice_hostname  = "voice.veronica-agent.com"
      voice_area_code = "205"
      openai_project_id = "proj_qnaIpxtc3PddMxEKQUeqry4O"
      voice_model = "gpt-realtime-2.1-mini"
      # Currently available voices:
      # alloy (female)
      # ash (male)
      # ballad (male, accent)
      # coral (female)
      # echo (male)
      # fable (unavailable for realtime)
      # nova (unavailable for realtime)
      # onyx (unavailable for realtime)
      # sage (female)
      # shimmer (female, low)
      # verse (male, high)
      # marin (female, recommended)
      # cedar (male, recommended)
      voice_voice    = "marin" # Steven's preference
      voice_greeting = "Veronica speaking, what can I do for you?"
      # How long the driver lets the audio path bridge before speaking the
      # greeting. Too short clips the greeting's start ("...ronica
      # speaking"); too long is dead air after the pickup.
      voice_greeting_settle_ms = 500
      voice_instructions = <<-EOT
        You are Veronica, an AI personal assistant.
      EOT
    }
  }
}
