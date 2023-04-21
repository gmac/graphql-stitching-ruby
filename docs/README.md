## GraphQL::Stitching

This module provides a collection of components that may be composed into a stitched schema.

![Library flow](./images/library.png)

Major components include:

- [Client](./client.md) - an out-of-the-box setup for performing stitched requests.
- [Composer](./composer.md) - merges and validates many schemas into one graph.
- [Supergraph](./supergraph.md) - manages the combined schema and location routing maps. Can be exported, cached, and rehydrated.
- [Request](./request.md) - prepares a requested GraphQL document and variables for stitching.
- [Planner](./planner.md) - builds a cacheable query plan for a request document.
- [Executor](./executor.md) - executes a query plan with given request variables.

Additional topics:

- [Stitching mechanics](./mechanics.md) - learn more about building for stitching.
