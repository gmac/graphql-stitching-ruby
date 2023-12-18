```shell
curl -X POST http://localhost:3000 \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ gateway remote }"}'
```

```shell
curl http://localhost:3000 \
  -H 'Content-Type: multipart/form-data' \
  -F operations='{ "query": "mutation ($file: Upload!) { gateway upload(file: $file) }", "variables": { "file": null } }' \
  -F map='{ "0": ["variables.file"] }' \
  -F 0=@file.txt
```
