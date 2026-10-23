# Anilite

A native iOS companion for anime and manga, built in SwiftUI with a Metal fluid simulation behind every screen. Anilite treats a franchise as one connected universe of seasons, films, manga and spin-offs. It learns your taste, plans your watching, and keeps spoilers out of sight until you're ready.

Data comes from the public [AniList](https://anilist.co) GraphQL API. Anilite is independent and is not affiliated with AniList, any studio or any publisher. It never hosts or links to unlicensed video or scans.

## What's inside

| Area | Highlights |
| --- | --- |
| **Discover** | Mood Match (natural-language and mood chips), a "Tonight" plan sized to your free time, a For You feed scored against your Taste DNA, revival suggestions for dropped titles, and trending titles filtered by Spoiler Shield. |
| **Find** | Free-text discovery ("short cozy fantasy, no romance, finished airing") parsed into AniList filters, shown as removable chips, plus recent searches. |
| **Universe Atlas** | Each franchise as a map you can fly through: a web of titles, characters, voice actors, creators, studios and themes that grows when you tap a node, or a timeline that lays the same map out by release year with people in lanes above and below. The two layouts morph into each other. A list view is also available. |
| **Pathfinder** | Watch and read orders, canon and filler guidance for long-running shows, completion times, and where the anime ends so you know where to pick up the manga. |
| **Title detail** | The page takes on the title's artwork: a blurred cover with marbled ink in colours read from its pixels, depth parallax, shared-element hero transitions, spoiler-aware synopsis, characters, staff, relations, recommendations and official streaming links (regional availability shown only when it can be verified). |
| **Library** | Offline-first lists synced with AniList (or kept locally), smart shelves with rules, a binge planner with weekly time budgets, an airing calendar with reminders, a journal and history. |
| **You** | Taste DNA (genre and theme strands, vibe radar, taste evolution, bridges between interests), archetype card, achievements, and an animated yearly recap. |
| **People** | Profiles for any AniList user (stats, favourites, recent activity, compatibility with you), follow and unfollow, a feed from the people you follow, and suggestions for people with your taste, found through reviews and activity on the titles you rated highest. Add friends in person with a QR code, or share a Taste DNA link. Also spoiler-safe shared lists and watch clubs with schedules and standing. |
| **Concierge** | A guide for newcomers: explains terms, picks starter titles, says where to start a franchise and whether a show's filler can be skipped. |

**Spoiler Shield** runs through the whole app. Episode descriptions, spoiler tags, character fates and late-series relations are hidden according to your progress and chosen level, and you can unlock spoilers per title.

## Design

The backdrop is painted and the foreground is inked. A stable-fluids simulation runs on the GPU, and every screen's backdrop is a window onto that one simulation, so the ink flows unbroken from page to page. Touches stir it. Pages with artwork (a title, a character, a creator, a studio, someone's profile, the Discover card in view, what you're watching in Library, the top search result) show that artwork blurred beneath the ink, in its own colours, and dissolve to the next one when it changes. In front of that, surfaces are solid, titles are set in a serif, and motion is short and eased with no bounce.

## Engineering

- **Architecture**: an `AniliteKit` Swift package holds the models, AniList client, sync engine, caching and every recommendation, planning and spoiler engine. It has no UI code and is tested on Linux and macOS. The app target holds only SwiftUI, Metal and platform code.
- **Network use**: GraphQL queries are batched, with per-request cache policies, rate-limit handling (`Retry-After`, exponential backoff), request coalescing and an on-disk response cache. Library edits queue offline and sync when the device is back online.
- **Performance**: images are downsampled to display size and cached in memory and on disk. The fluid simulation and the Atlas scale through an `EffectsBudget` that responds to Low Power Mode, thermal state and Reduce Motion: 60 fps at full, 30 fps when balanced, and a single still frame when minimal. Off-screen backdrops pause.
- **Accessibility**: Dynamic Type, VoiceOver labels and combined elements, Reduce Motion, Reduce Transparency and Increase Contrast fallbacks.
- **Tests**: the `AniliteKit` unit tests cover the engines, decoding, sync and networking. `AniliteTests` covers app logic: reminder planning, settings migration, routing and text formatting.

```
App/Sources
├── App/        entry point, root view, tab shell
├── Core/       AppModel, Router, settings, OAuth, reminders, image pipeline
├── Design/     theme, surfaces, fluid simulation (Metal), artwork backdrops, effects budget
├── Shared/     media cards, rails, async content, hero transitions
└── Features/   Discover, Find, Atlas, Pathfinder, Detail, Library, You, Social, Concierge, People, Onboarding
Packages/AniliteKit   models, networking, sync, engines (+ tests)
```

## Install the app

Each CI run publishes an **unsigned IPA**. Tagged versions also attach it to a [GitHub Release](https://github.com/aequate/anilite/releases).

1. Download `Anilite-unsigned.ipa`, either from the latest release or from the `Anilite-ipa-N` artifact of a successful [Actions run](https://github.com/aequate/anilite/actions).
2. Sign and install it with one of these tools:
   - **AltStore / SideStore**: open the IPA from Files with AltStore, or use **My Apps → +**. It is signed with your free Apple ID and needs refreshing every 7 days.
   - **Sideloadly**: connect your iPhone, drop in the IPA, enter your Apple ID and press Start.
   - **Your own certificate**: `codesign` or a re-sign tool such as `fastlane resign` with your provisioning profile.
3. On iOS 16 or later, turn on **Settings → Privacy & Security → Developer Mode** the first time. Then trust the developer certificate under **Settings → General → VPN & Device Management**.

Anilite requires iOS 17.0 or later.

### Signed builds from CI

If these repository secrets are set, the workflow also exports an installable, signed `Anilite-signed.ipa`:

| Secret | Value |
| --- | --- |
| `IOS_CERTIFICATE_P12` | base64 of your distribution certificate `.p12` (`base64 -i cert.p12`) |
| `IOS_CERTIFICATE_PASSWORD` | the `.p12` password |
| `IOS_PROVISIONING_PROFILE` | base64 of a profile for `app.anilite.ios` |
| `IOS_TEAM_ID` | optional; read from the profile if omitted |
| `IOS_EXPORT_METHOD` | optional: `release-testing` (default, ad hoc), `debugging`, `app-store-connect` or `enterprise` |

Certificates and profiles never live in the repository: `*.p12` and `*.mobileprovision` are gitignored.

## Connecting AniList

Anilite works without an account. You can keep a local library, or follow any public AniList profile read-only. To sign in and edit your AniList lists:

1. Create a client at [anilist.co/settings/developer](https://anilist.co/settings/developer) with the redirect URL `anilite://auth-callback`.
2. Add its numeric client ID as the repository secret `ANILIST_CLIENT_ID`. CI injects it into `Info.plist` at build time. For a local build, pass `ANILIST_CLIENT_ID=12345` to `xcodebuild`.

Without a client ID, the sign-in buttons are hidden and everything else still works. Sign-in uses AniList's implicit grant. The token is kept in the Keychain.

## Build locally

You need macOS with Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Anilite.xcodeproj

# command line
xcodebuild test -project Anilite.xcodeproj -scheme Anilite -destination 'platform=iOS Simulator,name=iPhone 17'
swift test --package-path Packages/AniliteKit   # also runs on Linux
```

## Data and content

- Metadata and artwork come from AniList under its [API terms](https://docs.anilist.co/guide/terms-of-use). Artwork belongs to its rights holders. Anilite credits AniList on every detail screen and links back to the source page.
- Anilite respects AniList's rate limit, caches responses, and doesn't scrape other sites.
- "Where to watch" lists only the official links AniList provides. A region is shown as available only when the data confirms it.
- Adult titles are filtered out.
- The camera is used only to scan friend QR codes. Nothing is recorded or uploaded.
