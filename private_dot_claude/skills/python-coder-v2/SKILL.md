---
name: python-coder-v2
description: Python design rules — type-system-first structure, immutability by default, behavior/data separation, effects at the edges, and a minimal public surface. Use when writing or reviewing Python code.
---

# python-coder-v2

Standing rules. Apply continuously while working — there are no pause gates.

**Derived from [`CORE_VISION.md`](CORE_VISION.md), which is authoritative.** Every rule below
carries a derivation tag. A rule that cannot be traced to a principle there is a defect — cut
it, or amend the vision. Never resolve a conflict in this file's favour.

Tags: `[P1]` structure in the type system · `[P2]` immutable by default · `[P3]` behavior
separable from data · `[P4]` effects at the edges · `[P5]` minimal public surface ·
`[Pn×Pm → Ck]` a resolved collision · `[hygiene]` a stated convention, no principle parent ·
`[gate]` tooling.

Target: **Python 3.13** (`requires-python >= 3.13`, ruff `py313`, basedpyright `3.13`). Rules
naming a later feature state their fallback.

---

## 1. Choosing a type

**A container whose keys or positions are a fixed, known set is a type, not a container.** `[P1]`

The target is `dict[str, Any]` used as a record, and positional tuples used as records.
Explicitly **legitimate**: homogeneous mappings, counters, caches, accumulator sets, and
`**kwargs` forwarding. A dict is wrong when its keys are a schema, not when it is a dict.

### Selection `[P1]`

| Need | Reach for |
|---|---|
| Fixed field set, value semantics, validated | `@dataclass(frozen=True, slots=True)` |
| Fixed field set that **is** a JSON payload crossing a boundary | `TypedDict` — a dict at runtime, no validation, no methods |
| Fixed field set that genuinely *is* a tuple — coordinates, RGB, multi-return | `NamedTuple` (see the leak in §1.2) |
| A distinct identity over an existing type, zero runtime cost | `NewType` |
| Closed set of named constants with identity | `Enum` / `StrEnum` |
| Closed set of values, no class needed | `Literal[...]` |
| Closed set of *alternatives with different fields* | Tagged union — §4 |
| Structural contract, including over types you do not own | `Protocol` |
| Nominal contract **plus** shared implementation | ABC — §5 |
| Genuinely open, homogeneous mapping | `dict[K, V]` |
| Identity, lifecycle, or required mutation | A plain class, with a stated reason |

Discriminating axes, when the table above is ambiguous: are the keys **closed or open**; does it
**cross a serialization boundary**; is it a **value or an entity**; must it be **hashable**; does
it need **runtime validation**; is it a **product** of fields or a **sum** of alternatives.

### 1.1 `Any` is quarantined at the boundary `[P1]`

Untyped input is parsed into typed structures **once, at the edge**. Interior code never sees
`Any` and never sees `dict[str, Any]`. No function returns `Any` or an untyped mapping.

### 1.2 `NamedTuple` — scoped, with a documented leak `[P1×P2 → C3]`

`Point(1, 2) == (1, 2)` is `True`, and instances unpack and index. That is nominal distinctness
lost — P1's whole purchase. Use it only where tuple-ness is the point: coordinates, colour
triples, `divmod`-shaped returns, cheap positional records at a hot boundary.

Do **not** hand-write `__eq__` to close the leak. Needing nominal equality is the signal that a
frozen dataclass was the right tool.

### 1.3 `TypedDict` — read-only at the edge, parsed for state `[P1×P2 → C2]`

- **Boundary payload** — deserialized, read, converted, dropped: annotate items `ReadOnly[...]`.
- **Held as state** — stored, passed inward, kept across calls: **parse into a frozen dataclass.**
  Not optional. `ReadOnly` is check-time only; the runtime object is a plain `dict` and
  `d["k"] = v` succeeds.

`ReadOnly` is `typing.ReadOnly` on 3.13+ and `typing_extensions.ReadOnly` below it. At the 3.12
target, the `typing_extensions` path applies. **If you import `typing_extensions`, declare it as
a dependency** — it is currently only present transitively, and a transitive dependency is not a
guarantee.

### 1.4 `NewType` `[P1]`

The cheapest way to give an existing type a distinct identity:

```python
TrimmedName = NewType("TrimmedName", str)
```

Enforcement is **check-time only**. `TrimmedName("  raw  ")` type-checks anywhere. It buys a
checker-enforced discipline, not a runtime guarantee — say so rather than over-trusting it.

### 1.5 Construction co-location `[P1 → C1, C6]`

**A type and its parse/construction functions live in the same module.** The parse function is
the only thing that establishes what the type guarantees; a guarantee you cannot find is a
guarantee you cannot audit.

This is the *narrow* rule. There is no broad "all functions operating on a type live with it"
rule — it was evaluated and cut (see `CORE_VISION.md`). Do not reintroduce it.

---

## 2. Immutability

### 2.1 `frozen=True` on every dataclass `[P2]`

Mutability requires a stated reason at the definition site:

```python
@dataclass(frozen=False)  # mutable: streaming accumulator, single-threaded, scoped to parse_corpus
class _ParseAccumulator:
    ...
```

The comment carries the *reason*; the explicit `frozen=False` carries the *decision*. Neither
alone distinguishes a choice from an oversight.

Rules for the escape, as enforced by a static immutability checker:

| | |
|---|---|
| **Reason floor** | **20 characters.** A shorter one is reported, not honoured — the value of an escape hatch is entirely in its reason. |
| **Placement** | Anywhere within the reported node's line span. A multi-line `@dataclass(...)` may carry it on the closing parenthesis. |
| **Spoofing** | Suppressions are read from `tokenize` COMMENT tokens, so `items.append("# mutable: ...")` does not suppress anything. |
| **Coverage** | One token for all three P2 diagnostics. On a decorator line carrying two, one comment silences both. |

Verified consequences:

| | Behavior |
|---|---|
| `obj.field = v` on a frozen instance | `FrozenInstanceError` |
| `obj.newattr = v` on a frozen instance | `FrozenInstanceError` — new attributes are blocked too |
| `frozen=True, eq=True` | `__hash__` generated; usable as a dict key or set member |
| `frozen=False, eq=True` | `__hash__` is `None` — **unhashable** |
| Non-frozen subclass of a frozen base | `TypeError: cannot inherit non-frozen dataclass from a frozen one` |

That last row means frozen-ness must be uniform down a hierarchy. A consistent default avoids
the problem entirely.

**Frozen is shallow.** A frozen dataclass holding a `list` is mutable. Field types must be
immutable: `tuple`, `frozenset`, `Mapping`. P1's container discipline is what makes P2 real.

### 2.2 Functions do not mutate their arguments `[P2]`

```python
def normalize(items: list[str]) -> None:   # NO — mutates the caller's list
    items.sort()

def normalized(items: Sequence[str]) -> tuple[str, ...]:   # YES
    return tuple(sorted(items))
```

Accept `Sequence` / `Mapping` / `Iterable` in parameters and return a concrete immutable type.
This is not annotation cosmetics — it is P2's enforcement mechanism, because it makes mutation a
type error instead of a convention.

### 2.3 `slots=True` on every dataclass `[P1 → C1]`

State the derivation honestly, because it is narrow: **under `frozen=True`, slots adds nothing
to ordinary assignment** — frozen already raises for any name. Its memory and attribute-access
benefits are real but derive from no principle here.

Its one correctness contribution is C1's escape hatch. Verified:

```python
object.__setattr__(obj, "nmae", v)   # frozen, no slots -> SILENT; creates a junk attribute
object.__setattr__(obj, "nmae", v)   # frozen + slots   -> AttributeError
object.__setattr__(obj, "name", v)   # frozen + slots   -> works; real fields still writable
```

That is the one place this document permits a string-keyed assignment no type checker can
verify. Slots is what makes it fail loudly.

**Exemption — one:** a third-party or framework requirement for instance `__dict__`. Everything
else routes rather than exempts:

| Situation | Route |
|---|---|
| `functools.cached_property` — raises `TypeError: No '__dict__' attribute ... to cache` | Use a module-level `@lru_cache(maxsize=...)` function taking the instance. `frozen=True, eq=True` makes it hashable, and behavior moves to a free function `[P3]`. **Bound `maxsize`** — `lru_cache` holds strong references and an unbounded cache over long-lived instances leaks. |
| Needs weak-referencing | `weakref_slot=True` (3.11+), not an exemption |
| Zero-arg `super()` in a method — `slots=True` returns a *replacement class*, so the `__class__` cell is stale and it raises `TypeError` | Unreachable under §3.2: inheritance is limited to variant bases carrying zero methods |
| A decorator applied below `@dataclass(slots=True)` sees the discarded class | Reorder |
| Base class not slotted — instances keep a `__dict__` and slots buys nothing | Apply down the hierarchy or not at all |
| Tests monkeypatching new attributes onto instances | A test-design problem. Use a fixture or a purpose-built mutable double. |

### 2.4 Mutable defaults `[P2]`

`@dataclass` raises `ValueError` at class-creation time for a bare mutable default — the runtime
already enforces this, no linter needed. Use `field(default_factory=...)`, and prefer an
immutable factory (`tuple`, `frozenset`).

### 2.5 `kw_only=True` on every dataclass `[hygiene]`

No principle parent — this is a stated convention closing a concrete hazard. Without it, a field
without a default cannot follow one that has a default:

```
TypeError: non-default argument 'b' follows default argument 'a'
```

The case that bites is inheritance: **a base carrying any defaulted field blocks every subclass
from adding a required field.** Verified. `kw_only=True` eliminates the ordering entirely, and
§4's sum types already require it — making it universal is the consistent choice, not an extra
rule.

**The standard decorator is therefore:**

```python
@dataclass(frozen=True, slots=True, kw_only=True)
```

Each of the three is separately justified above. Deviating from any one requires the reason that
rule specifies.

---

## 3. Construction, validation, and methods

### 3.1 Validity, and where it is established `[P1×P2 → C1]`

**Validity is a predicate over the instance's own field values, decidable at construction, with
no I/O and no reference to other objects.** That is the test — not "does this make the object
correct or useful," which is circular and cannot sort real cases.

| Placement | Rule |
|---|---|
| **Boundary parse** — the field type only admits valid values | **Primary.** Parse once at the edge; the interior never re-checks. |
| **`__post_init__`** | Permitted, **raise-only** under `frozen=True`. Raises from the error hierarchy (§7), never a bare `ValueError`. Keep it thin — extract `_validate_x(value) -> None` if it exceeds a couple of lines. |
| **Low-level attribute write in `__post_init__`** | Documented escape for normalization when a second type is disproportionate. Requires `slots=True` (§2.3). |
| **Factory / `classmethod` only** | **Prohibited.** `dataclasses.replace()` re-runs `__init__` and `__post_init__` but has no knowledge of your factory — every `replace()` call would produce an un-normalized instance. Verified. |

`replace()` *does* re-run `__post_init__`, so validation survives it. That is an argument for
keeping validation there rather than moving it out.

### 3.2 Inheritance `[P3]`

For **closed variant sets** only — a base carrying shared fields and **zero methods**. Never for
code reuse. If you are inheriting to share an implementation, you want a free function.

### 3.3 Methods `[P3]`

Permitted when they are **pure functions of the instance**. Anything that performs I/O,
orchestrates other objects, or mutates state is a free function.

### 3.4 Dunder methods `[P3]`

A dunder declares that the type **has** an algebraic or protocol structure. Admit it when that
is true; reject it when an operator is standing in for a verb.

| Admitted | Rejected |
|---|---|
| `Money.__add__` — Money is additive | `Pipeline.__call__` meaning "run it" |
| `Version.__lt__` — versions are ordered | `Validators.__or__` meaning "chain these" |
| `__len__` / `__iter__` / `__contains__` on a real collection | `Query.__getitem__` meaning "fetch a row" |
| `__eq__`, `__hash__`, `__repr__` | `__rshift__` as DSL composition |

Rules:

- **Prefer generated.** `frozen=True, eq=True, order=True` gives comparison and hashing for free.
- Hand-writing `__eq__` → pass `eq=False` explicitly, so the decorator's precedence is not in play.
- `__eq__` and `__hash__` are defined together or not at all.
- `__eq__` returns `NotImplemented` for foreign types — never `False`, never a raise.
- Dunders are pure and total. `[P4]`

---

## 4. Sum types `[P1]` `[P1×P3 → C4]`

A closed set of alternatives with variant-specific fields. The field-sharing inheritance below
is permitted because P3 objects to inheritance for *code reuse*, not for field sharing — the
base carries fields and zero methods.

```python
@dataclass(frozen=True, slots=True, kw_only=True)
class _FindingBase:
    message: str

@dataclass(frozen=True, slots=True, kw_only=True)
class LineFinding(_FindingBase):
    kind: Literal["line"] = "line"
    line: int

@dataclass(frozen=True, slots=True, kw_only=True)
class RangeFinding(_FindingBase):
    kind: Literal["range"] = "range"
    start: int
    end: int

AnyFinding = LineFinding | RangeFinding
```

Required, not optional: `[P1]`

- A **`Literal` discriminant field** (`kind` above). Without it the checker cannot narrow.
- **`assert_never`** in the exhaustive branch (`typing.assert_never`, 3.11+):

  ```python
  def render(f: AnyFinding) -> str:
      match f:
          case LineFinding():
              return f"line {f.line}"
          case RangeFinding():
              return f"{f.start}-{f.end}"
          case _:
              assert_never(f)
  ```

  Adding a variant without handling it becomes a **type error**. That is the entire value of a
  sum type; without it you have a union.

- All construction keyword-only (`kw_only=True` on every level) — no field-ordering to manage.

**`isinstance` and union aliases.** `isinstance(x, AnyFinding)` **works** for a plain assignment
alias — it is a `types.UnionType`. It raises `TypeError` only for a PEP 695 `type AnyFinding = ...`
alias or a subscripted generic. Verified on 3.13; the plain-alias form is valid from 3.10.
Exporting a base class purely to enable `isinstance` is unnecessary.

---

## 5. Contracts

Route in this order: `[P1]` `[P3]`

1. **Closed set of variants with different fields → a tagged union (§4).** Neither `Protocol` nor
   ABC provides exhaustiveness. Most reaches for an ABC are this case in disguise.
2. **`Protocol`** — the default for behavior contracts. Structural, so types you do not own can
   satisfy it, and implementers import nothing.
3. **ABC** — only when *both* hold: you own every implementation, **and** there is dynamically
   dispatched shared implementation with a meaningful default. Shared implementation with no
   per-variant dispatch is a free function taking the `Protocol`.

### 5.1 `Protocol` conformance is asserted at the definition site `[P1]`

Structural typing surfaces a conformance bug far from its cause. Pin it next to the implementation:

```python
_: SomeProtocol = SomeImpl(...)   # conformance check at import
```

Verified limits of `@runtime_checkable`: `isinstance` checks **member presence only, not
signatures** — a method with the wrong signature still passes. `issubclass` raises
`TypeError: Protocols with non-method members don't support issubclass()`.

### 5.2 Callable fields versus contracts `[P1×P3 → C5]`

A `Callable[...]` field is legitimate when the function is genuinely **per-instance data** —
varied per instance, composed, partially applied, collected into a sequence. Use a `Protocol`
when it is a **named contract**, especially a multi-operation one.

Consequences to accept when using a callable field: functions compare by identity under
`eq=True`, and closures do not pickle.

---

## 6. Effects

**I/O, the clock, randomness, the network, the filesystem, and mutation live in a thin shell.
The core is pure.** `[P4]`

The boundary split: `[P4×P1 → C6]`

```python
def read_manifest(path: Path) -> str: ...          # impure — the shell
def parse_manifest(raw: str) -> Manifest: ...      # pure — lives with Manifest (§1.5)
```

Reading is an effect. Parsing is a function. Keeping them separate is what makes the parse
testable without a filesystem.

---

## 7. Errors

No `Result` type — Python has no `?` operator and no enforced handling, so it produces ceremony
without the guarantee. Instead: `[P1]` `[P4]`

### 7.1 Expected outcomes are encoded in the return type `[P1]` `[P4]`

| Failure kind | Mechanism |
|---|---|
| **Expected, recoverable** — malformed input, absent record, parse failure | **Return type.** `X \| None`, or a tagged union of outcomes (§4). |
| **Invariant violation** — programmer error, unrepresentable state reached | **Raise.** Permitted in the pure core; it is a bug report, not a control-flow path. |

Raising is an effect — a non-local transfer invisible in the signature. This split is what makes
"no `Result`" compatible with P4.

### 7.2 Hierarchy `[P1]`

Structure — `[P1]`:

- One root exception per package, inheriting `Exception`. Everything the package raises descends
  from it, so callers get a single catchable boundary. Never inherit `BaseException`.
- Domain errors may multiply-inherit the matching builtin, so existing callers keep working:
  `class InvalidTierError(CorpusError, ValueError)`.

Discipline — `[P4]`:

- Never exceptions for control flow. An exception is an effect; using one as a branch makes the
  effect invisible in the signature and defeats §7.1's split.

Discipline — `[hygiene]`:

- `raise ... from err` always. No bare `except:`. No `except Exception:` without a re-raise.

---

## 8. Public surface

**Everything is private unless deliberately exposed.** `[P5]`

### 8.1 Symbols `[P5]`

- `_`-prefix is the **default** for every module-level symbol and every attribute.
- Public means: no prefix, **and** listed in `__all__`.
- Both are required. `__all__` alone does not prevent `from mod import _thing`; the prefix alone
  does not declare intent.

**Enforcement, as verified — not as assumed:**

| Target | `reportPrivateUsage` (basedpyright strict) | ruff `SLF001` |
|---|---|---|
| `_symbol` imported across modules | **caught** | not caught |
| `obj._attr` accessed outside its class | **caught** | **caught** |
| `from pkg._module import x` | **not caught** | **not caught** |

Symbol privacy is a **gate failure**. Module privacy is a **convention only** — no tool checks it.
Do not write or read the module rule below as though it were enforced.

### 8.2 Modules and packages `[P5]`

Both mechanisms, at different levels:

- `_`-prefixed module names for genuinely internal machinery — stdlib precedent: `_thread`,
  `_collections_abc`.
- A curated `__init__.py` for the package's surface; submodules stay unexported.

**Cost, stated up front:** Rust encodes visibility in a modifier (`pub`); Python encodes it in
the *name*. Promotion is therefore a rename that churns every internal caller. That friction is
retained deliberately — it makes promotion an act rather than a drift.

### 8.3 Tests `[P5 × testability → C7]`

A test directory can be exempted from `reportPrivateUsage` via a path-scoped type-checker
override. This is what lets an extracted `_validate_x` be unit-tested without inflating the
public surface.

The exemption is scoped to the test directory and is **not** a general escape hatch. Widening it,
or moving non-test code into it, defeats P5 where it matters.

---

## 9. Naming `[hygiene — discharges P3's discoverability cost]`

No principle parent. It exists because **P3 creates a real regression and owes a mitigation**:
with methods, `obj.` enumerates every operation on a type. With free functions that affordance
is gone, and no IDE can answer "what functions take a `Tier`?" as a first-class query.

A broad co-location rule was the obvious fix and was cut (see `CORE_VISION.md`). This convention
is the replacement: it restores **search-quality** discovery, which is weaker than autocomplete
and is the honest ceiling here.

- **The type's name appears in the name of every function that operates on it.** `parse_tier`,
  `validate_tier`, `render_tier`. "What can I do with a `Tier`?" becomes `grep '_tier'`.
- **Verb first**: `<verb>_<noun>`. The noun is the primary type — the one taken, or the one
  returned when the function constructs.
- **A module is named for the type it owns.** `tier.py` holds `Tier` and `parse_tier`. This is
  the same grouping §1.5 already requires for construction; naming makes it visible from the
  import line.
- **Information-free verbs are banned**: `get_`, `handle_`, `process_`, `do_`, `manage_`. If the
  verb does not narrow what the function does, it is not a name.
- **Booleans read as predicates**: `is_`, `has_`, `should_`.

Everything else about naming is PEP 8 and belongs to the linter, not to this document.

---

## 10. Docstrings and comments `[hygiene]`

Document what the annotation **cannot** carry. Under strict typing, an `Args:` entry that
restates the parameter's type is noise.

Every **public** function (§8.1) carries a Google-style docstring: a one-line summary, then only
the sections that add information —

- **Units, ranges, and encodings** not visible in the type (`seconds`, `0.0–1.0`, `UTC`).
- **Ownership** — whether a returned container may be retained or must be copied.
- **`Raises:`** for every exception the caller is expected to handle.
- **Effects** — I/O, network, filesystem. If the function is in the shell, say so. `[P4]`

Private helpers carry a docstring when the *why* is non-obvious, not by default.

Comments explain **why**, never what: a hidden constraint, a workaround, a subtle invariant.
**No TODOs** — an unresolved question belongs in `docs/planning/`, where it has an owner and a
blocker, not in a source file where it decays silently.

---

## 11. Quality gates `[gate]`

Run in order. Fix each before moving to the next.

1. Type checker (strict mode) — zero errors
2. Formatter — formatting clean
3. Linter — zero lint errors
4. Test suite — no new failures **against a baseline captured before editing**
5. A static P2 immutability check, if one is wired into the project — missing `frozen=True`,
   in-place parameter mutation, and a frozen bypass without `slots=True`

Notes:

- **Capture the baseline first.** Run the test suite before the first edit. "No new failures" is
  unverifiable after the fact.
- Gates 1–3 should cover tests as well as source. A pre-commit or edit-time hook that lints only
  part of the tree does not guarantee the rest of the tree is clean — **hook-clean does not mean
  CI-clean.**
- A P2 immutability check is a **lower bound** by construction. Aliasing defeats it in both
  directions — `a = items; a.append(1)` and `o = object; o.__setattr__(...)` both pass. It
  catches the syntactically visible case and claims nothing more.

---

## Deliberately not covered

These are absences by decision, not oversight. Do not add them ad hoc; amend
[`CORE_VISION.md`](CORE_VISION.md) first if the case for one changes.

| Topic | Why not |
|---|---|
| **Function arity limits / keyword-only thresholds** | No principle parent — arity is ergonomics. Thresholds are arbitrary, get argued with, and are partially tool-covered already (ruff `PLR0913`). The one arity-adjacent rule with a concrete failure behind it — `kw_only=True` on dataclasses — is in §2.5, where it belongs. |
| **Generics and `TypeVar` guidance** | The only variance case that actually bites here is already resolved in §2.2: accept `Sequence`/`Mapping`, return a concrete immutable type. A general section would be speculative, and it would invite the over-abstraction it has no way to police. |
| **PEP 8 naming beyond §9** | Belongs to the linter. Restating it here creates a second source that can drift from the tool that enforces it. |
| **A broad module co-location rule** | Evaluated and cut. Derives from no principle, collides with P4 for I/O-touching operations, and has no decision procedure for functions taking two types. The narrow form is §1.5; the discoverability cost is §9. Full reasoning in `CORE_VISION.md`. |
| **`Result`-style error returns** | Python has no `?` operator and no enforced handling. §7.1 gets the same benefit for expected outcomes without the ceremony. |
