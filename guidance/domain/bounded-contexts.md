# Bounded contexts

## Design

- Apply strategic DDD (bounded contexts, ubiquitous language) even where tactical DDD is not used, and scale its overhead to the size of the app.
- Duplicate similar models in each bounded context and integrate them rather than share one model across contexts. Sharing creates bad coupling, and DRY has exceptions here.

## Design and plan

- Treat strategic domain-driven design as the most important part of planning. Before building, settle the domain language, how the work breaks into contexts, the lifecycle, inputs and outputs, data sources and swim lanes.
