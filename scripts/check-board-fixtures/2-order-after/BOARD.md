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
- After: first-task
- Source: fixture
- Problem: Something is open. The 400-line limit and 284 lines: are sizes, not line numbers.
- Done when: it is closed.
- Refs: `Foo.bar`; `BarView` (`onTap`).

### cycle-a
- Type: task
- Area: domain
- Order: 50
- After: cycle-b
- Source: fixture
- Problem: Something is open. The 400-line limit and 284 lines: are sizes, not line numbers.
- Done when: it is closed.
- Refs: `Foo.bar`; `BarView` (`onTap`).

### cycle-b
- Type: task
- Area: domain
- Order: 60
- After: cycle-a
- Source: fixture
- Problem: Something is open. The 400-line limit and 284 lines: are sizes, not line numbers.
- Done when: it is closed.
- Refs: `Foo.bar`; `BarView` (`onTap`).

### later-task
- Type: task
- Area: domain
- Order: 30
- After: gone-task, big-epic
- Source: fixture
- Problem: Something is open. The 400-line limit and 284 lines: are sizes, not line numbers.
- Done when: it is closed.
- Refs: `Foo.bar`; `BarView` (`onTap`).

### same-order
- Type: task
- Area: domain
- Order: 30
- Source: fixture
- Problem: Something is open. The 400-line limit and 284 lines: are sizes, not line numbers.
- Done when: it is closed.
- Refs: `Foo.bar`; `BarView` (`onTap`).

### text-order
- Type: task
- Area: domain
- Order: soon
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
