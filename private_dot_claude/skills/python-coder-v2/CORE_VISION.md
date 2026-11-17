# CORE_VISION

**Authoritative over [`SKILL.md`](SKILL.md).** Authority runs one way. A rule in `SKILL.md`
that cannot be traced to a principle here is a defect — cut the rule or amend this document.
A conflict is never resolved in `SKILL.md`'s favour.

This file is read at **audit time**, not apply time. `SKILL.md` is what loads while code is
being written; the derivation tags it carries are what connect the two. If you are here to
settle whether a rule earns its place, you are in the right file.

---

## What belongs here

> **Does this statement stay true if the language version, the tooling, or the repository
> changes?**
> Yes → this file. No → `SKILL.md`.

Principles, their derivations, the conflict procedure, and the collision register live here.
Every construct-specific rule, version-gated feature, naming convention, and tooling gate
lives in `SKILL.md`.

---

## Grounding

**ML-family statically-typed functional discipline** — the Haskell / OCaml / F# / Elm lineage.
Algebraic data types, illegal states made unrepresentable, parsing at the boundary,
immutability by default, effects isolated from a pure core.

**Rust is the familiar exemplar, not the source.** It is a descendant of that tradition and
most readers know it better than they know ML. It is cited only where the borrow actually
transfers — see the ports table below.

**"Data-oriented" is deliberately not claimed.** The term has two established meanings and
both argue *against* P1:

| Tradition | Prescribes | Compatible with P1? |
|---|---|---|
| Clojure-style data-orientation | Generic structures — maps and vectors — few of them, many functions over them; validation via schema at boundaries only | **No.** An argument *for* raw dicts. |
| Data-oriented design (game dev) | Memory layout: struct-of-arrays, cache-line packing, bulk transforms | **Irrelevant.** Python gives no control over layout. |

Naming either would license exactly the code this document exists to reduce.

---

## Principles

Five, **co-equal**. There is no precedence ordering. Each purchases a property none of the
others provide.

### P1 — Structure lives in the type system

Every value with a fixed shape has a named type. Untyped containers are for genuinely open,
homogeneous data. `Any` is quarantined at the boundary and never reaches the interior.

**Buys:** errors caught at check time rather than run time; signatures that state what they
accept; refactors that fail loudly instead of silently.

**Derivation:** the ML tradition's central claim — a program's invariants belong in its types,
where a machine checks them, not in its documentation or its tests, where a human must.

### P2 — Immutable by default; mutation is declared

Values do not change after construction. Mutation is available, but it requires a stated
reason at the point it is used. This covers dataclass fields *and* function arguments — a
function does not mutate what it is given.

**Buys:** safe sharing without defensive copying; hashability; functions that are actually
pure rather than nominally pure.

**Derivation:** Rust's `let` versus `let mut`, and the ML default. Mutation is not forbidden;
it is made visible.

### P3 — Behavior is separable from data

Inheritance is for closed variant sets, never for code reuse. Mutation and I/O live in
functions, not methods. Methods are permitted when they are pure functions of the instance;
so are dunder methods that implement a structure the type genuinely has.

**Buys:** behavior testable without constructing the world; operations added without touching
the type; no behavior coupling through a method resolution order.

**Derivation:** `impl` blocks are declared separately from the struct, and traits are
implementable outside the type they extend. Note what this is *not*: Rust has methods and uses
them everywhere. "No methods" is not a Rust property and is not a principle here.

### P4 — Effects live at the edges

I/O, the clock, randomness, the network, the filesystem, and mutation are pushed into a thin
shell. The core is pure.

**Buys:** P3's testability claim becomes true rather than aspirational; a call's behavior is
readable from its signature.

**Derivation:** the functional core / imperative shell decomposition. Without it, "behavior
lives in free functions" yields free functions that open sockets, and nothing is gained.

### P5 — The public surface is minimal and declared

Every symbol, module, and package is private unless deliberately exposed. Exposure is an act,
not a default.

**Buys:** a bounded change surface. You can only safely change what nobody can reach.

**Derivation:** Rust's privacy default — items are private, `pub` is opt-in, at every level.
This is one of the cleanest borrows available: unlike `impl` co-location it carries no
coherence-constraint dependency, so it transfers without its motivating machinery.

---

## Rust: what ports and what does not

The reference is honest only where it states its own limits.

| Rust idiom | Ports? | Vehicle / reason |
|---|---|---|
| Newtype (`struct UserId(u64)`) | **Yes** | `NewType`, or a single-field frozen dataclass when validation is wanted |
| `enum` with per-variant payload | **Yes** | Discriminant tag + frozen dataclasses + union alias + exhaustiveness assertion |
| Immutable-by-default bindings | **Yes** | Frozen construction (P2) |
| No `null` | **Yes** | `X \| None` under a strict checker; never a sentinel typed `Any` |
| Privacy by default | **Yes** | P5. `pub` is opt-in at every level in Rust; the borrow needs nothing else. |
| `impl` block separate from the struct | **Partly** | Behavior in module-level functions. See the co-location note below. |
| Exhaustive `match` | **Partly** | The checker narrows on a discriminant; an explicit never-assertion is the enforcement |
| Trait as a behavior contract | **Partly** | Structural or nominal contracts exist, but there is no coherence checking and no orphan rule |
| `Result<T, E>` over exceptions | **No** | No `?` operator and no enforced handling. Forcing it produces ceremony without the guarantee. Exceptions are the idiom; the hierarchy is made explicit instead. |
| Ownership / borrowing | **No analogue** | — |
| Zero-cost abstraction | **No** | Every abstraction here costs |

**Co-location, specifically.** Rust co-locates behavior with data because **coherence** requires
that either the type or the trait be local — a soundness constraint on trait resolution. Python
has no trait resolution and therefore no derived need. A broad "the module is the impl block"
rule was evaluated and **cut**: it derives from no principle here, collides with P4 for any
I/O-touching operation, and has no decision procedure for functions taking two types — which is
most of them. Only the narrow form survives, and it survives on P1: a type and its
parse/construction functions live together, because the parse function is the only thing that
establishes what the type guarantees, and a guarantee you cannot find is a guarantee you cannot
audit.

The discoverability cost that broad co-location would have addressed is real and is handled as
a naming convention in `SKILL.md`, where a stated convention needs no principle parent.

---

## Conflict procedure

The principles are co-equal. There is no ranking to appeal to, so conflicts are adjudicated
individually and recorded.

**Meta-rule.** When two principles collide, the rule that preserves a **check-time guarantee**
wins over the rule that preserves **ergonomics**.

This is a ranking of what is at stake in a specific cell, not a ranking of the principles.

**Unresolved collisions do not produce rules.** A rule whose collision has not been adjudicated
is not written. The section at the end of this file is where those live, and it is meant to
stay short.

---

## Collision register

| ID | Collision | Resolution |
|---|---|---|
| **C1** | **P1 × P2.** Immutable construction blocks in-place normalization, but P1 wants the normalized form guaranteed. | Parse at the boundary so the field type only admits normalized values. A direct low-level attribute write is the documented escape when a second type is disproportionate. **Factory-only normalization is prohibited** — the stdlib replace operation re-runs construction and bypasses factories, silently producing un-normalized instances. |
| **C2** | **P1 × P2.** A typed-dict boundary payload is a mutable mapping at runtime. | Read-only field qualifiers at the edge, **and** parse into a frozen type for anything held as state. The qualifier is check-time only and provides no runtime guarantee, so it is not sufficient alone. |
| **C3** | **P1 × P2.** A named tuple is immutable (P2 ✓) but compares equal to a plain tuple, defeating nominal distinctness (P1 ✗). | Kept, scoped to values that genuinely *are* tuples. The equality leak is documented rather than patched — needing nominal equality is the signal that a frozen record type was the right tool. |
| **C4** | **P1 × P3.** Tagged unions with shared fields require inheritance, which P3 restricts. | **Dissolved.** P3 objects to inheritance for *code reuse*, not for *field sharing*. A variant base carrying fields and zero methods does not trigger the concern. The collision was an artifact of P3 being stated too loosely. |
| **C5** | **P1 × P3.** A callable-valued field erases the operation's name; P1 wants named structure. | Criterion, not a ban. A callable field when the function is genuinely per-instance **data** — composed, partially applied, collected. A named contract when the operation is part of an interface. P1 holds the default. |
| **C6** | **P4 × P1.** The boundary parse sits at the edge, but must be pure to be testable. | Split it. Reading is impure and belongs in the shell; parsing is pure and belongs with the type. |
| **C7** | **P5 × testability.** Extracting a private helper so it can be unit-tested is exactly what a private-usage check forbids. | Tests are exempt from the private-usage check by path-scoped configuration. Rejected: *"if it needs a test, it's public"* (inverts P5 and inflates the surface for a testing reason) and *"test only through the public surface"* (contradicts the extraction guidance that motivates the helper). |

**Evaluated and not registered.** A P3 × P4 collision over function placement — the type's
module versus the boundary module — arises only under a broad co-location rule. That rule is
cut, so the collision does not exist. Recorded so it is not re-derived.

---

## Unresolved collisions

None outstanding.

When one is found: record it here, do not write the rule it would have produced, and resolve it
before the next rule that touches either principle. This section growing past two or three
entries is a signal that the principle set is under-determined and needs amendment, not that
the list needs managing.

---

## Amending this document

A principle is added when a rule the codebase genuinely needs derives from none of the existing
five and the addition does not require re-ranking anything — co-equality makes that cheap.
P5 was added this way, on 2026-07-29, when API surface proved underivable from P1–P4.

When a principle changes, every `SKILL.md` rule tagged with it is reviewed. The tags exist so
that review is a grep, not an archaeology exercise.
