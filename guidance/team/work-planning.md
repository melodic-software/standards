# Work planning

## Interview and plan

- Take a full inventory of current state before planning, and treat defining the problem and sizing the work as separate concerns.
- Group related issues under a theme or parent, interview them until their intent is captured, then implement in parallel in dependency order; split a large domain into ordered phases under a roadmap, with a handoff between them.

## Design and plan

- Plan at the fidelity the question needs (discussion, sketches, breadboards, prototypes, working code), and use higher fidelity more often now that agents make it cheap.
- Lock the overall shape and conventions first, and make shared foundations sound before variants. Prove one piece end to end, starting with pieces that feed each other and that shift more work to automation, reach a repeatable pattern, then expand step by step. Make it work first; naming and polish come after.

## Plan

- Keep complexity and effort as separate estimate measures, and leave time-based estimates out of agent output by default, giving general size instead, as a setting.
- Set realistic but aggressive numeric targets with deadlines and replan when progress stalls. Forecast from measured flow (merge rate, items opened versus closed) and leave on-track work undisturbed. Under a deadline, keep full scope and cut only when it is at risk.
- Break oversized work into right-sized dependent items grouped by single responsibility, under a parent when useful, before an agent picks it up. Be suspicious of many small items with separate branches and reviews, and give agents one shared, evidence-based rubric for when a split is justified. Escalate to heavier planning on signals of size and unknowns, not a fixed count.
- Order work by value per unit of time (cost of delay divided by duration): a cheap fix goes first when that ratio is higher, not because it is cheap. Where a known constraint limits flow, work on the constraint first. Cost of delay is an estimate; treat the scores as rough.
