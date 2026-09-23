# MarketFlow Mobile — Implementation Specification

## Goal

Build a polished Flutter marketplace application demonstrating production-style mobile engineering and the skills expected from a Flutter developer working across product, design, and backend teams.

## Required stack

- Flutter stable
- Dart stable
- Riverpod
- Dio
- GoRouter
- local persistence/cache

A Node.js/NestJS + PostgreSQL backend is preferred when practical. Otherwise, use a deterministic mock/local API while preserving clean repository and data-source boundaries.

## Core features

- Authentication
- Product feed
- Categories
- Search
- Filters
- Sorting
- Pagination
- Product details
- Favorites
- Shopping cart
- Persisted cart
- Checkout simulation
- Order history
- Profile/account
- Pull-to-refresh
- Offline/error state
- Optimistic UI where appropriate

## Networking

Implement:
- timeout handling
- API error mapping
- auth interceptor
- response parsing
- cancellation where useful
- retry only where appropriate

## State management

Use Riverpod and keep application state out of UI widgets.

Model loading, success, empty, and error states clearly.

## Architecture

Use a layered structure separating:
- presentation
- application/state
- domain
- data
- networking
- persistence

## Responsive UI and UX

The app should look like a real commercial mobile product, not a tutorial.

Use:
- reusable components
- consistent spacing
- loading skeletons
- polished empty states
- meaningful error/retry states
- Material 3
- light/dark themes if practical

## Accessibility

Include:
- semantics
- text scaling
- suitable touch targets
- keyboard/focus support where applicable
- accessible form validation

## Performance

Demonstrate:
- efficient lists
- image caching
- pagination/lazy loading
- search debounce
- minimal rebuilds
- const widgets

Document why each optimization matters.

## Testing

Include:
- unit tests
- repository tests
- Riverpod/state tests
- widget tests
- integration-style flow where practical

## CI

GitHub Actions:
- format check
- flutter analyze
- flutter test

## Release readiness

Document Android and iOS release processes and verify Android release builds if the environment allows.

## Documentation

Create:
- docs/ARCHITECTURE.md
- docs/STATE_MANAGEMENT.md
- docs/API.md
- docs/TESTING.md
- docs/PERFORMANCE.md
- docs/ACCESSIBILITY.md
- docs/RELEASE.md
- docs/AI_WORKFLOW.md
- docs/INTERVIEW_GUIDE.md

INTERVIEW_GUIDE.md should map interview questions directly to code in this repository.

## Verification

Before completion:
- dart format .
- flutter analyze
- flutter test
- flutter build apk --release if possible
- flutter build appbundle if possible
- inspect for secrets
- verify README and docs

Do not claim success without command output.
