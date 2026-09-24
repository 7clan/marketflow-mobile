# Accessibility

Accessibility here is a **test-enforced contract**, not a checklist: the
widget suite (`test/widget/`) asserts the semantics tree, the geometry and
the text-scale behavior directly. Everything below names the real
implementation and the real test that verifies it.

## Touch targets — 48 dp minimum, verified by geometry

- `FavoriteButton` (`lib/presentation/widgets/favorite_button.dart`) wraps an
  `IconButton` in a `Semantics(button: true, label: …)` — Material's padding
  gives the *interactive* area 48 dp even though the visual icon is 40 dp.
- `QuantityStepper` (`lib/presentation/widgets/quantity_stepper.dart`) —
  both +/- buttons carry explicit `Semantics` labels and meet 48 dp.
- `AppTextFormField`'s password-visibility toggle — labeled 48 dp
  `IconButton`.

**The test:** `test/widget/product_card_test.dart` → *"the favorite button
meets the 48dp touch target"* walks the actual semantics tree
(`tester.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode`,
recursively via `visitChildren`), finds the node whose label contains
"to favorites", and asserts `node.rect.width >= 48 && node.rect.height >= 48`
— the *accessible* geometry, not the visual widget size. (Non-deprecated
semantics-tree access, per the pattern proven on the CareRoute codebase.)

## Semantics labels on every icon-only control

- `FavoriteButton`: state-following label — "Add *title* to favorites" /
  "Remove *title* from favorites" (plus a tooltip).
- `QuantityStepper`: labels reflect the action and bounds (minus disabled at
  minimum).
- Password toggle (`app_text_form_field.dart`): "Show password" /
  "Hide password" — it re-reads correctly after the first toggle.
- Screen action bars: search/filters app-bar buttons use `tooltip:`
  ('Search products', 'Filters and sorting' — `product_feed_screen.dart`).
- Decorative `Icon`s carry `semanticLabel: 'Error'`, `'Image unavailable'`,
  `'Order'`, `'Seller'`, `'Order placed'`, `'View order details'`
  (`error_view.dart`, `product_card.dart`, `orders_screen.dart`,
  `product_detail_screen.dart`); pure decoration (the discount badge) is
  `IgnorePointer` + hidden from the a11y tree.

**The tests:** *"form fields and the submit button expose semantics"*,
*"the password field is obscured with a labeled toggle"*
(`login_screen_test.dart`); *"exposes a single a11y label covering the card
tap target"* (`product_card_test.dart` — the whole card is one
`Semantics(button: true, label: 'Title, $price')` so TalkBack reads one
useful unit instead of five fragments).

## Accessible form validation — `errorText`, client and server

- Every form field is `AppTextFormField`; validation failures return a
  string from `validator` → Material renders it as `errorText`, which screen
  readers announce on focus (the platform standard channel).
- Server-side 422 field errors flow into the **same** mechanism:
  `ValidationException.fieldErrors` → the screen's `_fieldErrors` map → the
  field's `validator` returns it → `errorText`.
- Detail: once a password has been revealed, a failing validation keeps it
  visible so the user can fix it while reading the error
  (`app_text_form_field.dart`).

**The test:** *"empty submit shows per-field inline errors"* and *"a
malformed email is rejected inline"* (`login_screen_test.dart`).

## Live regions — errors and loading announced

- Login error banner: `Semantics(liveRegion: true)` around the error
  container (`login_screen.dart:152`) — a failed sign-in is announced, not
  silently recolored.
- Checkout: the submitting/failure banners and the success confirmation are
  live regions (`checkout_screen.dart:566,619`).
- Loading: `SkeletonAnnouncer` wraps skeleton areas in
  `Semantics(label: 'Loading', liveRegion: true)` (`skeleton.dart:125`) and
  the individual gray blocks are `ExcludeSemantics` — assistive tech hears
  "Loading" **once**, politely, instead of reading out anonymous rectangles.

**The tests:** *"the message is exposed to assistive technology"*
(`error_view_test.dart`), *"wrong credentials surface a mapped error banner"*
+ the banner live-region assertion (`login_screen_test.dart`), *"the first
page renders skeleton cards, not a spinner"* asserts
`find.bySemanticsLabel('Loading')` finds exactly one
(`product_feed_screen_test.dart`).

## Autofill hints — keyboard/password-manager integration

- Login/register: `AutofillHints.email`, `AutofillHints.password`
  (`login_screen.dart:131,143`).
- Checkout address: `name`, `streetAddressLine1`, `addressCity`,
  `addressState`, `postalCode`, `countryName`, `telephoneNumber`
  (`checkout_screen.dart:290–358`) — a full autofillable address form.
- Appropriate `TextInputType` (email) and `textInputAction` (next/done)
  flow, with `onFieldSubmitted` submitting the form from the keyboard.

## Text scaling — 2.0× safe by construction

Strategy: **no fixed-height containers around text**; flexible/wrapping
layout instead:

- `ProductCard` is the contract carrier: the image is the `Expanded`
  element, the title ellipsizes at 2 lines, metadata rows wrap
  (`product_card.dart` — documented in the class docstring).
- `Wrap` for chip rows and prompts (`login_screen.dart:203` "Don't have an
  account? Create one", feed filter chips, order meta lines).
- Every screen body scrolls (`SingleChildScrollView`/`ListView`), forms are
  width-constrained (`ConstrainedBox(maxWidth: 480)`), totals rows use
  `Expanded` with ellipsis where needed.

**The test:** `product_card_test.dart` — *"no overflow at logical width
360"* and *"no overflow at width 360 with 2.0x text scale"*
(`TextScaler.linear(2.0)` via `MediaQuery`) with
`expect(tester.takeException(), isNull)`. The card is the smallest, most
text-dense cell in the app — if it survives 2.0× at the narrowest supported
width, the screens built from it (which give it *more* room) do too.

## Keyboard / focus support

- `textInputAction: next` chains login fields; `done` submits
  (`onFieldSubmitted`).
- Submit buttons disable while a request is in flight (`_submitting`), so
  double activation is impossible — including via assistive tech.
- Interactive elements are buttons/`InkWell`/chips — standard focus order
  and activation semantics; the card itself is one `Semantics(button: true)`
  unit with a single activation point.

## The verification matrix

| Contract | Test | File |
| --- | --- | --- |
| 48 dp favorite target (semantics geometry walk) | "the favorite button meets the 48dp touch target" | `test/widget/product_card_test.dart` |
| Single combined card label | "exposes a single a11y label covering the card tap target" | `test/widget/product_card_test.dart` |
| Inline field errors | "empty submit shows per-field inline errors", "a malformed email is rejected inline" | `test/widget/login_screen_test.dart` |
| Error banner announced (live region) | "wrong credentials surface a mapped error banner" | `test/widget/login_screen_test.dart` |
| Field + submit semantics, labeled obscure toggle | "form fields and the submit button expose semantics", "the password field is obscured with a labeled toggle" | `test/widget/login_screen_test.dart` |
| Error view message exposed | "the message is exposed to assistive technology" | `test/widget/error_view_test.dart` |
| Loading announced once, skeletons over spinners | "the first page renders skeleton cards, not a spinner" | `test/widget/product_feed_screen_test.dart` |
| 360 dp + 2.0× text scale no-overflow | "no overflow at logical width 360", "no overflow at width 360 with 2.0x text scale" | `test/widget/product_card_test.dart` |

Not covered by automated tests (manual/QA territory, honestly): real
TalkBack/VoiceOver session recordings, focus traversal order on complex
screens, and localized string review — the app is English-only.
