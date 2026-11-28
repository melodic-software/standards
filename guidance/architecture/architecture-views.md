# Architecture views

## Design

- Design architecture visuals to span macro to micro levels, including diagrams of how domain terms relate.
- Each repository declares its own identity, owner and outgoing dependencies once, next to its code. Cross-repository work starts from a view generated from those declarations, never edited by hand. Definitions no single repository owns are kept once in a shared catalog the declarations reference.

## Design and build

- Keep an accurate map of every external dependency a system relies on, and show each automated component's purpose wherever it is displayed.
