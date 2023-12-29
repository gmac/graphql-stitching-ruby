# File uploads example

This example demonstrates uploading files via the [GraphQL Upload spec](https://github.com/jaydenseric/graphql-multipart-request-spec).

Try running it:

```shell
cd examples/file_uploads
bundle install
foreman start
```

This example is headless, but you can verify the stitched schema is running by querying a field from each graph location:

```shell
curl -X POST http://localhost:3000 \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ gateway remote }"}'
```

Now try submitting a multipart form upload with a file attachment, per the [spec](https://github.com/jaydenseric/graphql-multipart-request-spec?tab=readme-ov-file#curl-request). The response will echo the uploaded file contents:

```shell
curl http://localhost:3000 \
  -H 'Content-Type: multipart/form-data' \
  -F operations='{ "query": "mutation ($file: Upload!) { gateway upload(file: $file) }", "variables": { "file": null } }' \
  -F map='{ "0": ["variables.file"] }' \
  -F 0=@file.txt
```

This workflow has:

1. Submitted a multipart form to the stitched gateway.
2. The gateway server unpacked the request using [apollo_upload_server](https://github.com/jetruby/apollo_upload_server-ruby).
3. Stitching delegated the `upload` field to its appropraite subgraph location.
4. `HttpExecutable` has re-encoded the subgraph request into a multipart form.
5. The subgraph location has recieved, unpacked, and resolved the uploaded file.