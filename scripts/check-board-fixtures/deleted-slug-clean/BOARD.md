# Board

Fixture.

## Epics

### big-epic
- Type: epic
- Area: domain
- Order: 20
- Source: fixture
- Problem: Something is open. The 400-line limit and 284 lines: are sizes, not line numbers.
- Done when: it is closed.
- Refs: `Foo.bar`; `BarView` (`onTap`).

## Tasks

### first-task
- Type: task
- Area: domain
- Order: 10
- Source: fixture
- Problem: Something is open. The 400-line limit and 284 lines: are sizes, not line numbers.
- Done when: it is closed.
- Refs: `Foo.bar`; `BarView` (`onTap`).

### later-task
- Type: task
- Area: domain
- Order: 30
- After: big-epic
- Source: fixture
- Problem: Something is open. The 400-line limit and 284 lines: are sizes, not line numbers.
- Done when: it is closed.
- Refs: `Foo.bar`; `BarView` (`onTap`).

## Drift

### drift-doc
- Type: drift
- Area: domain
- Order: 40
- Source: fixture
- Problem: Something is open. The 400-line limit and 284 lines: are sizes, not line numbers.
- Done when: it is closed.
- Refs: `Foo.bar`; `BarView` (`onTap`).
