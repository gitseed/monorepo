# human-sandbox

A orbstack sandbox that should have all the credentials and tools you need to work.

## gcloud

Authenticated via a bind mount of the host's `~/.config/gcloud`. On the host,
run both once:

```
gcloud auth login
gcloud auth application-default login
```

The first covers the `gcloud` CLI; the second produces the ADC file that tofu's
google provider and client libraries read.
