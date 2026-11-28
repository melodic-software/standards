# Api design

## Design

- Support the features downstream consumers need, even when your own setup does not use them.

## Design and review

- Treat a component's public contract as the one thing you must not break once others depend on it; everything behind it is free to change. While you are the only consumer, rename and break interfaces freely.
- A convention shared across workflows is a public contract: document it and make every workflow conform to it.
