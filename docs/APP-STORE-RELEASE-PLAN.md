# MacAmp App Store release plan

September 29, 2026 · Working plan for the first Mac App Store release

This plan starts from the current MacAmp MVP candidate. It covers the work required to produce a sandboxed TestFlight build, validate that build, prepare the product page, and submit a release candidate to App Review. `PRODUCT-DESIGN.md` remains the authority for product behavior; `docs/REQUIREMENTS-LEDGER.md` remains the evidence ledger.

Uploading a build to App Store Connect or submitting it to App Review is an external release action. Prepare and validate the exact artifact first, then obtain the product owner's approval for the upload or submission.

## 1. Current baseline

The application, audio pipeline, playlist, EQ, skin system, media commands, persistence, and visualization MVP exist and the automated suite passes. The release foundation now includes:

- `scripts/package-app.sh` builds with SwiftPM, assembles the bundle manually, and ad-hoc signs it.
- The bundle identifier remains provisional `com.macamp.app`; version is `1.0.0`, build `1`.
- The Xcode archive is universal `arm64` and `x86_64`; the ad-hoc SwiftPM package remains native-host architecture for local development.
- App Sandbox entitlements, a privacy manifest, an original asset-catalog icon, the native Xcode target/scheme, archive/export scripts, and strict bundle validation are implemented.
- An unsigned universal archive passes local validation. Distribution signing/profile, final App ID, upload, and App Store Connect processing require publisher credentials.
- The English metadata, privacy/compliance answers, review notes, support/privacy copy, screenshot plan, and final external-action checklist are prepared in `docs/app-store/`.
- Public use of the `MacAmp` name is blocked pending a naming/rights decision because it conflicts with a historical commercial audio player name.
- Manual release gates remain for VoiceOver, performance, long-run playback, sleep/wake, physical audio routes, network-volume recovery, and supported macOS versions.

Developer ID signing and notarization are a separate lane for distribution outside the Mac App Store. They are not acceptance criteria for this plan.

## 2. Release gates

Use these gates in order. A later gate cannot waive an earlier failure.

| Gate | Outcome | Acceptance condition |
| --- | --- | --- |
| AS-0 Decisions | Stable release identity and scope | Name, bundle ID, price, architectures, minimum macOS, territories, and support owner are recorded |
| AS-1 Sandboxed app | MacAmp works with App Sandbox enabled | Local development-signed build passes file access, relaunch, network-volume, playlist, and skin workflows |
| AS-2 Distribution archive | Uploadable release artifact | Xcode archive/export validates with the intended App ID, distribution signing, profile, entitlements, resources, version, and build number |
| AS-3 Release candidate | Product quality evidence is complete | Automated suite and manual matrix pass on the exact archived commit; no open release-blocking defects |
| AS-4 TestFlight | Store-delivered build works | App Store Connect processes the upload and internal TestFlight smoke/soak checks pass |
| AS-5 App Review ready | Product page and compliance are complete | Metadata, screenshots, privacy, age rating, content rights, review notes, pricing, territories, and agreements have no missing fields |
| AS-6 Submission | Candidate is sent to App Review | Product owner approves the exact build/version and App Review submission |

## 3. Decisions to close first

Record decisions in `docs/APP-STORE-DECISIONS.md`. None should block the sandbox implementation unless it changes code signing or the build matrix.

| Decision | Default recommendation | Why it matters |
| --- | --- | --- |
| Product name | Clear `MacAmp` for App Store name availability and trademark risk; keep a backup name | Name and artwork must not imply affiliation with Winamp or another product |
| Bundle ID | Use a reverse-DNS identifier under a domain controlled by the publisher | The App ID, provisioning profile, App Store record, and persisted container depend on it |
| Version | Ship the first public release as `1.0.0` with monotonically increasing build numbers | App Store Connect associates uploads by bundle ID, version, and build |
| Architecture | Prefer universal `arm64` + `x86_64` if the audio dependencies build and Intel testing is available; otherwise explicitly ship Apple silicon only | The current artifact is `arm64` only |
| Minimum OS | Keep macOS 14 only if it can be tested; otherwise raise the minimum to the oldest tested release | The store listing must match actual compatibility |
| Business model | Free for the first release unless a paid launch is intentional | Paid distribution adds agreements, tax, banking, and pricing work |
| Territories | Start with territories whose compliance requirements can be completed | EU availability requires a declared and, where applicable, verified trader status |
| Privacy posture | No accounts, ads, analytics, tracking, or off-device collection in 1.0 | This matches the current offline implementation and simplifies the privacy label |

## 4. Workstream AS-A — App Store build foundation

**Owner:** release coordinator  
**Dependencies:** AS-0 bundle ID and architecture decisions for the final archive; implementation can begin with placeholders.

1. Add a macOS Xcode application target and shared scheme that consume the existing Swift package modules. Keep SwiftPM as the core build graph.
2. Add Debug, Release, and AppStore configurations. AppStore must use Release optimization and must not embed test fixtures or development-only tools.
3. Add an asset catalog with a complete Mac app icon set and wire it into the bundle.
4. Move production bundle metadata into the target configuration:
   - final bundle identifier;
   - version/build settings;
   - Music application category;
   - copyright;
   - supported document types and exported UTIs for `.macampskin` and the legacy `.chuckskin` association;
   - encryption/export-compliance declaration after dependency review.
5. Create `MacAmp.entitlements` with the minimum capabilities required by AS-B.
6. Add reproducible scripts for clean archive, export, and local validation. Secrets, team IDs, certificate names, and profiles must be supplied through Xcode or untracked local configuration.
7. Add artifact checks for bundle structure, architecture, Info.plist, icon, embedded provisioning profile, entitlements, signature, resources, and third-party notices.

**Deliverables**

- Xcode project, shared scheme, asset catalog, entitlements, and build configurations.
- `scripts/archive-app-store.sh` and `scripts/export-app-store.sh` wrappers for documented Xcode archive/export operations.
- `scripts/validate-app-store.sh` that fails on ad-hoc signing, missing sandbox entitlement, missing resources, or unexpected architecture.
- Updated build instructions that distinguish development, App Store, and any future direct-download artifacts.

**Acceptance**

- A clean unsigned or development-signed archive can be reproduced without personal secrets.
- With authorized credentials present, Xcode creates a Mac App Store distribution archive with a Team ID and matching profile.
- `MacAmp.app` launches from the archive and contains the same skin, codec, playlist, and visualization resources as the tested development build.

## 5. Workstream AS-B — Sandbox and persistent file access

**Owner:** library/file-access implementer with release coordinator integration  
**Dependencies:** AS-A entitlements scaffold.

Use the minimum initial entitlements:

- `com.apple.security.app-sandbox = true`
- `com.apple.security.files.user-selected.read-write = true`
- `com.apple.security.files.bookmarks.app-scope = true`

Do not add broad Music-folder, Downloads-folder, network client/server, automation, or temporary-exception entitlements unless a tested feature requires one and the reason is documented.

Validate every path by user action and by restoration:

1. Open one audio file, multiple files, and a selected folder through standard panels.
2. Drag files and folders from Finder.
3. Import M3U/M3U8/PLS playlists with relative, missing, unauthorized, and network-volume entries.
4. Export playlists and skin packages through a save panel.
5. Import, preview, apply, export, and remove `.macampskin` packages.
6. Quit and relaunch with a populated queue; restored items must play without selecting them again when their bookmarks remain valid.
7. Handle stale or denied bookmarks with locate/reauthorize UI; clearing the playlist must always work.
8. Test `/Volumes/Music/lidarr`, then disconnect and reconnect the volume. Playback must fail clearly, remain responsive, and recover after reauthorization or reconnection.
9. Verify every successful `startAccessingSecurityScopedResource()` has a balanced stop after playback, metadata inspection, prefetch cancellation, and errors.
10. Verify persisted data writes only to the app container or a user-selected export URL.

**Acceptance**

- The sandboxed build completes the full workflow without `Operation not permitted`, stale-access loops, lost exports, or silent playlist removal.
- Existing non-sandbox sessions migrate safely or start cleanly with an understandable reauthorization path.
- Repeated playback and metadata scanning do not leak security-scoped access leases.

## 6. Workstream AS-C — Privacy, security, dependencies, and rights

**Owner:** release coordinator  
**Dependencies:** final binary and dependency graph from AS-A.

1. Generate Xcode's privacy report for the release archive.
2. Confirm ZIPFoundation and all linked code against Apple's current third-party SDK requirements.
3. Add a valid `PrivacyInfo.xcprivacy` when required by the final APIs/dependencies or use it to declare the final no-tracking/no-collection posture. Do not invent required-reason API declarations that the macOS binary does not use.
4. Complete an export-compliance review. If the final app does not use non-exempt encryption, set the corresponding Info.plist declaration and retain the decision evidence.
5. Run static checks on the release bundle for unexpected network endpoints, private frameworks, debug paths, test resources, executable downloads, and unsigned nested code.
6. Verify all bundled assets, fonts, skins, source fixtures, and screenshots are original or licensed for distribution. Keep ZIPFoundation's license and third-party notices in the app bundle.
7. Perform App Store name availability and trademark clearance for `MacAmp`. Keep Winamp and other third-party names, logos, product art, and implied affiliation out of the icon, bundled skins, screenshots, description, subtitle, and keywords.
8. Publish a plain-language privacy policy and support page. The policy must match the binary and App Store privacy answers.

**Acceptance**

- Privacy report, export-compliance decision, dependency inventory, licenses, and asset provenance are stored as release evidence.
- App Store Connect privacy answers accurately describe the final binary and third-party code.
- Support and privacy URLs are public, stable, and contain current contact information.

## 7. Workstream AS-D — Release validation

**Owner:** QA owner independent of the changed subsystem where practical  
**Dependencies:** sandboxed AS-A/AS-B release candidate.

All evidence must identify the exact commit, version/build, archive, machine, architecture, and macOS version. Test the archived application rather than substituting the ad-hoc development bundle.

### Automated gate

- Run the complete Swift test suite from a clean checkout.
- Run artifact validation and App Store delivery validation.
- Run codec/container probes for MP3, AAC-LC, HE-AAC, ALAC, FLAC at 44.1/96/192 kHz, WAV/AIFF, Vorbis, and Opus.
- Retain regression coverage for malformed files, bookmarks, queue recovery, skin-package validation, visualization lifecycle, and persistence migration.

### Manual gate

- Perform the spoken VoiceOver checklist and keyboard-only navigation.
- Verify Increase Contrast and Reduce Motion across all bundled skins and scale settings.
- Test launch, playback, seek, EQ, visualization, compact mode, window resizing, snapping, fullscreen, relaunch, and clear-playlist behavior.
- Test built-in output, headphones or USB audio, Bluetooth where available, output removal, sleep/wake, and media keys.
- Run a multi-hour mixed-format playlist from local storage and `/Volumes/Music/lidarr` while measuring underruns, CPU, memory, and visualization frame cost.
- Test a fresh install, an upgrade over prior persisted state, and recovery from a missing network volume.
- Test the oldest supported macOS and current macOS. Test both architectures if the release is universal.

Record results in `docs/TEST-REPORT.md` and update every affected row in `docs/REQUIREMENTS-LEDGER.md`.

**Acceptance**

- `A11Y-01`, `PERF-01`, `REL-01`, `DIST-01`, `DIST-02`, and `DIST-03` pass.
- No crash, data loss, unbounded skip loop, authorization regression, sustained audio underrun, or inaccessible primary control remains open.
- Any intentionally deferred feature is hidden or described accurately and is absent from store claims.

## 8. Workstream AS-E — App Store Connect and product page

**Owner:** product owner for account/legal choices; release coordinator for prepared content  
**Dependencies:** AS-0 identity; screenshots require the accepted AS-3 UI.

Prepare a reviewable metadata packet in `docs/app-store/`:

- app name and backup name;
- subtitle, description, keywords, promotional text if used, category, copyright, and release notes;
- support URL, privacy-policy URL, and marketing URL if used;
- one to ten screenshots showing real playback, playlist, EQ, skins, and visualization using distributable audio metadata/artwork;
- age-rating questionnaire answers;
- content-rights declaration;
- App Privacy answers;
- export-compliance answer;
- price, territories, and release method;
- App Review contact and notes with exact steps to import audio, exercise skins, open the visualizer, and restore a playlist;
- an original or redistributable test track if review would otherwise depend on the reviewer's personal files.

Account work:

1. Ensure Apple Developer Program membership and current agreements are active.
2. Register the explicit App ID and create the App Store Connect app record.
3. Confirm the App Store name and SKU.
4. Declare EU Digital Services Act trader status; complete verification if required for chosen territories.
5. For a paid app, complete the Paid Apps Agreement, banking, tax, and price schedule.

**Acceptance**

- App Store Connect shows no missing compliance, agreement, pricing, territory, privacy, age-rating, or metadata fields.
- Screenshots and copy match the submitted build and make no unsupported claims.
- Review notes explain non-obvious local-file authorization, skin packages, and network-volume behavior without referencing internal prototypes.

## 9. Workstream AS-F — TestFlight and submission

**Owner:** release coordinator  
**Dependencies:** AS-2 archive and product-owner approval to upload.

1. Upload the exact validated archive to App Store Connect.
2. Resolve processing errors and warnings in code or metadata; do not waive unexplained binary warnings.
3. Release the processed build to a small internal TestFlight group.
4. Repeat the sandbox/file/bookmark smoke test from the TestFlight-installed app.
5. Run a 24-hour soak period with representative daily use and review TestFlight crashes and feedback.
6. If fixes are required, increment the build number, repeat AS-2 through AS-4, and retire the superseded candidate.
7. Freeze the accepted build, metadata packet, privacy answers, and review notes.
8. Present the exact build/version and remaining known limitations to the product owner for submission approval.
9. Submit to App Review and track reviewer messages. Reproduce any rejection against the submitted build before changing scope.

**Acceptance**

- The TestFlight-installed build passes, not merely the locally archived copy.
- The selected build and product-page metadata are identical to the approved release candidate.
- App Review submission occurs only after AS-0 through AS-5 pass.

## 10. Execution waves

These workstreams can proceed with one integrator and bounded ownership. Do not let metadata work mutate the release target while sandbox and signing work is underway.

| Wave | Critical path | Parallel work | Exit |
| --- | --- | --- | --- |
| 1 | AS-A project/target, entitlements scaffold, artifact validator | AS-0 decisions; icon brief; support/privacy copy draft | Development-signed sandbox app launches |
| 2 | AS-B file-access and persistence matrix | AS-C dependency/privacy/IP audit; initial metadata packet | Full sandbox workflow passes |
| 3 | AS-A distribution archive and validation | AS-E screenshots/copy; AS-D automated suite | Processable App Store archive |
| 4 | AS-D manual release matrix and defect fixes | Complete account/compliance fields | Release candidate accepted |
| 5 | AS-F internal TestFlight and soak | Final metadata proofread | App Review-ready build |
| 6 | Submission after explicit approval | Reviewer-response preparation | App submitted |

Rough planning range: three to six focused engineering days for build/sandbox work, two to four days for validation and fixes, and at least one day of TestFlight soak. Account verification, name clearance, old-mac/Intel access, and App Review operate on external timelines.

## 11. Features that do not block 1.0

The following remain product backlog unless exposed or promised in the submitted build:

- visualization preset import/export;
- visualization shuffle;
- additional presets or skins beyond the current shipped set;
- online catalogs, streaming services, accounts, telemetry, or cloud sync;
- direct-download Developer ID signing, notarization, installer, and updater.

Fix defects in existing features before adding these. Store copy must describe only the behavior that passes AS-D in the submitted build.

## 12. Definition of done

MacAmp is ready to submit when all of the following are true:

- The release archive is App Store signed, provisioned, sandboxed, self-contained, and accepted by App Store Connect processing.
- Restored local and network-volume tracks remain authorized or provide a working reauthorization path.
- The exact TestFlight build passes automated, accessibility, performance, device-change, sleep/wake, long-run, clean-install, and upgrade tests.
- The application identity, icon, skins, screenshots, and metadata are original and cleared for distribution.
- Privacy, encryption, content rights, age rating, territories, trader status, agreements, pricing, and support information are complete and accurate.
- There are no visible unfinished controls, placeholder pages, release-blocking ledger rows, or known crash/data-loss/audio-stability defects.
- The product owner has approved the exact version/build for App Review submission.
