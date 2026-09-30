# MacAmp 1.0 submission checklist

## Complete locally

- [x] Native Xcode app target and shared App Store scheme
- [x] Debug, Release, and AppStore configurations
- [x] App Sandbox, user-selected read/write, and app-scoped bookmark entitlements
- [x] Privacy manifest and no-collection audit
- [x] Music category, document types, skin UTI, and encryption declaration
- [x] Original app icon asset catalog and compiled icon validation
- [x] Universal arm64 + x86_64 unsigned archive
- [x] Reproducible archive/export scripts with externalized team, identifier, version, and build
- [x] Bundle checks for identity, version, architecture, icon, resources, linked libraries, signature, profile, and entitlements
- [x] Third-party notices and dependency pinning
- [x] English metadata, privacy answers, compliance draft, review notes, support copy, and screenshot plan
- [x] Public privacy policy and issue-based support URLs; both returned HTTP 200 and repository Issues are enabled
- [x] Automated suite: 112 passed, 5 serial AudioComponent tests intentionally skipped and covered by AudioProbe lanes

## Account holder or external service required

- [ ] Choose a cleared product name. “MacAmp” is the name of a historical commercial audio player and is also in current third-party use; a legal/name-availability decision is required.
- [ ] Choose and register the final explicit bundle identifier. The project currently uses provisional `com.macamp.app`.
- [ ] Supply Apple Developer Team ID and install a valid Apple Distribution identity/profile. This Mac currently reports zero valid code-signing identities.
- [ ] Create the App Store Connect macOS app record; confirm name, SKU, primary language, bundle ID, and category.
- [ ] Enter the verified public privacy and support URLs in the App Store Connect record.
- [ ] Supply App Review contact name, email, and international-format phone number.
- [ ] Declare actual EU DSA trader status and choose territories.
- [ ] Confirm current agreements; confirm free price and manual release.
- [ ] Complete the age-rating questionnaire with the prepared answers.
- [ ] Capture and approve final 2560×1600 screenshots from the signed release candidate.
- [ ] Run the hands-on release matrix: VoiceOver/keyboard, contrast/reduced motion, sleep/wake, Bluetooth/USB/output removal, macOS 14, Intel hardware, mounted/disconnected network volume, upgrade, and multi-hour playback.
- [ ] Archive with signing, export, upload, and wait for App Store Connect processing.
- [ ] Install through internal TestFlight and repeat the sandbox/file-access smoke test and soak.
- [ ] Approve the exact processed build and submit it to App Review.

The unchecked items cannot be completed from source code alone because they require the publisher's legal choices, public contact details, Apple Developer credentials/account roles, physical test environments, or an external App Store Connect action.
