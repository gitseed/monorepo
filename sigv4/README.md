# sigv4

Builds `signing_names.json`: a map of every AWS service to its SigV4 signing name (the `service_name` envoy's `aws_request_signing` filter wants in the credential scope).

Service catalogs like SSM `/aws/service/global-infrastructure/services` and the [service reference API](https://servicereference.us-east-1.amazonaws.com/) use their own identifiers that only mostly match signing names (`accessanalyzer` vs `access-analyzer`, `cloudwatch` vs `monitoring`). The authoritative value is the `aws.auth#sigv4` trait each service team declares in its Smithy model, published in [aws/api-models-aws](https://github.com/aws/api-models-aws). This project pulls every model at HEAD and extracts the trait. `null` means the service doesn't sign with sigv4 at all.

Apply on a new laptop, or when AWS ships a service you want:

```sh
tofu -chdir=tofu init
tofu -chdir=tofu workspace select global
GITHUB_TOKEN=$(gh auth token) tofu -chdir=tofu apply
```

Needs the token: ~430 API calls per run, anonymous rate limit is 60/hr. Heads up that state is ~220MB — it carries every fetched model body.
