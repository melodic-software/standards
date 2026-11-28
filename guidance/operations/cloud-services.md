# Cloud services

## Design

- Never design around a provider's terms of service: when an approach would violate them (including automating a vendor's interactive-only apps), use the next best compliant option and point to the terms from the tool.

## Design and operate

- Learn a provider's real limits first, then work around them, and treat its rate limits and quotas as a shared budget: query efficiently and never hammer the service.
- Keep automation clear of free-tier quotas such as cache and artifact storage, because hitting one must never halt work.

## Design and build

- Cloud conventions state how app resources differ from personal developer resources, including subscriptions, resource groups and how personal machines are classified.

## Build and review

- Name cloud resources by the provider's current official naming conventions, and audit existing resources into line, not only new ones.
