Test container networking:

`container run --dns 203.0.113.113 --rm fedora/fedora:42 curl -4 --fail --silent --show-error --connect-timeout 2 --max-time 4 https://google.com/ --output /dev/null && echo 'outbound HTTPS OK'`

Build image:

`container build --pull --no-cache -t credentials-proxy --dns 203.0.113.113 -f main.containerfile .`

Run image:

`infisical run --env global --projectId b4d3e8f0-dec8-4bb7-bc71-bba7dd3401f0 -- container run --rm -it --name credentials-proxy --env OPENROUTER_API_KEY --dns 203.0.113.113 --publish 127.0.0.1:10000:10000 credentials-proxy`

Test openrouter:
`curl --fail-with-body --silent --show-error -H 'Authorization: wrong' http://127.0.0.1:10000/api/v1/key`
