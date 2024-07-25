## GraphQL::Stitching

This module provides a collection of components that may be composed into a stitched schema.

![Library flow](./images/library.png)

Major components include:

- [Client](./client.md) - an out-of-the-box setup for performing stitched requests.
- [Composer](./composer.md) - merges and validates many schemas into one graph.
- [Supergraph](./supergraph.md) - manages the combined schema and location routing maps. Can be exported, cached, and rehydrated.
- [Request](./request.md) - prepares a requested GraphQL document and variables for stitching.
- [HttpExecutable](./http_executable.md) - proxies requests to remotes with multipart file upload support.

Additional topics:

- [Stitching mechanics](./mechanics.md) - more about building for stitching and how it operates.
- [Subscriptions](./subscriptions.md) - explore how to stitch realtime event subscriptions.
- [Federation entities](./federation_entities.md) - more about Apollo Federation compatibility.
