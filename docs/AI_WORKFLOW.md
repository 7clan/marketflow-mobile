# AI-Assisted Development Disclosure

MarketFlow was built with AI assistance (a multi-agent workflow built around
the Z.ai Code tooling), under human direction and with machine-verifiable
quality gates. This document states plainly what that means — what the AI
did, what was verified, and where human judgment remains irreplaceable.

## How the work was organized

The project ran as a worklog-driven sequence of scoped agent runs, each
with a bounded mandate and each leaving a commit trail:

1. **Core/domain/data/state** — config, the `AppException` hierarchy +
   `ErrorMapper`, `ApiClient`/`AuthInterceptor`, theme, validators, the
   in-process mock marketplace server, secure session + SharedPreferences
   data sources, models, 5 repository impls, 9 controller providers.
2. **Presentation** — GoRouter shell with auth redirect, 15 screens, 11
   shared widgets, with the a11y/performance quality bar applied from the
   start (48 dp targets, live regions, builder lists, const).
3. **Tests** — the 215-test suite across core/data/state/widget/integration,
   written *against the implementation as it shipped* — and expected to
   find problems, which it did (four real bugs, four fix commits).
4. **Documentation** — this set, written from the actual source files with
   every claim traceable to a file, class or number.

A persistent worklog (`/home/z/my-project/worklog.md`) recorded every
phase's real outcome — including failures, dead-ends and environment
gotchas — so each successive run started from verified facts rather than
optimistic memory.

## What was verified (machine-checked)

| Claim | Verification |
| --- | --- |
| 215/215 tests pass | `flutter test`, group counts: core 4 files/74, data 5/63, state 6/55, widget 5/22, integration 1/1 |
| Static analysis clean | `flutter analyze` → "No issues found!" |
| Formatting clean | `dart format` → 0 changed files |
| Toolchain | Flutter 3.47.5 stable / Dart 3.13.4 |
| Four real bug fixes | Commits `29e1aa2`, `be23db5`, `9226ccb`, `2f24900`, each with a regression test |
| Docs traceable | Every documented path/class/number checked against source while writing |

CI (`.github/workflows/flutter_ci.yml`) re-runs the format/analyze/test
gates on every push and pull request, so the above remain enforced rather
than one-time claims.

## Where AI genuinely added value

- **Speed with discipline:** full-layer implementation in a fraction of
  calendar time, but always behind the same gates a human team would use —
  analyzer, formatter, tests, review.
- **Consistency:** the same error-mapping, sentinel-`copyWith`,
  stale-guard and a11y patterns applied across 14 providers and 15 screens
  without drift — because they were established early and tests enforced
  the consequences.
- **The four bug fixes are the best evidence of process value:** the AI
  wrote tests that caught its own concurrency bugs (provider-cycle
  deadlock, restore clobbering, stale notifier writes, raw 401 escape) and
  then fixed them with targeted commits. Tests written to *find* problems,
  not to decorate a README.

## Where human judgment led

- **Product decisions:** what the app is (marketplace, Material 3,
  feature list), the quality bar (accessibility as a test contract,
  honest release documentation), what to cut (no HTTP cache layer, no code
  generation).
- **Architecture review:** the layering, the in-process-backend tradeoff
  (real failure classes vs the fake-async zone cost), the decision to keep
  checkout state non-keepAlive, the pricing-rules-as-shared-pure-function
  design.
- **Truthfulness audit:** documentation claims were re-checked against the
  code (file paths, counts, prices, test names); the iOS "not verified"
  and debug-signing disclosures exist specifically so nothing in this repo
  overclaims.

## Known limitations of the process

- AI-generated code benefits from *adversarial* verification; the suite
  here is strong on seams and state machines, but coverage was
  prioritized, not exhaustive (e.g. no golden-image tests, no
  TalkBack/VoiceOver session recordings).
- Multi-agent runs inherit environment quirks; the fake-async-zone lesson
  and the bash display artifact (`[m` sequences) cost real time to
  root-cause and are documented so the next project starts ahead.
- Release builds for this repo were not yet executed at documentation
  time; `docs/RELEASE.md` keeps an explicit (currently empty) build
  verification log rather than claiming unrun commands as done.
