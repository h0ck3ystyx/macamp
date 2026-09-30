# MacAmp App Store decisions

Use this file to close the release decisions in `APP-STORE-RELEASE-PLAN.md`. A decision is final only when its status is `accepted`. Record the reason and date so a later build does not silently change store compatibility or identity.

| Decision | Proposed value | Status | Owner/action |
| --- | --- | --- | --- |
| Product name | Public name must be cleared; `MacAmp` has a documented historical commercial use and current third-party use | blocked | Product owner/legal owner chooses a cleared name; `Modular Player` is an unchecked fallback candidate |
| Bundle identifier | Reverse-DNS identifier under a publisher-controlled domain | pending | Product owner supplies domain; release coordinator registers App ID |
| Public version | 1.0.0; increment build number for every upload | accepted | Implemented in the project and validated archive; product owner requested store preparation |
| Architectures | Universal `arm64` + `x86_64`; Intel hardware QA still required | accepted | Universal archive built successfully on 2026-09-29 |
| Minimum macOS | macOS 14 if the full release matrix can run there | proposed | QA must provide macOS 14 evidence |
| Business model | Free first release | proposed | Product owner |
| Territories | Broad release after required compliance is complete | pending | Product owner |
| EU trader status | Declare the publisher's actual status and verify it if required | pending | Account holder |
| Privacy posture | No accounts, ads, analytics, tracking, telemetry, or off-device data collection | accepted | Source, dependency, entitlement, binary-string, and privacy-manifest review completed 2026-09-29 |
| Support owner | Public support contact and URL | pending | Product owner |
| Privacy policy | https://github.com/h0ck3ystyx/macamp/blob/main/PRIVACY.md | accepted | Public URL returned HTTP 200 on 2026-09-29 |
| Release method | Manual release after App Review approval | proposed | Product owner |

## Decision record

2026-09-29 — Public version
Value: 1.0.0, build 1 for the first candidate; every upload increments the build.
Reason: Apple identifies builds by bundle ID, version, and build number, and 1.0 represents the first public release.
Approved by: Product owner through the request to prepare the app for the store.
Implications: Project, package, validation, and metadata use 1.0.0.

2026-09-29 — Architectures
Value: Universal arm64 and x86_64.
Reason: The Xcode archive builds and validates both slices with all current dependencies.
Approved by: Release coordinator technical decision; final Intel hardware QA remains a release gate.
Implications: Archive validation requires both slices.

2026-09-29 — Privacy posture
Value: No collection or tracking.
Reason: MacAmp is offline and contains no network, account, advertising, analytics, or telemetry implementation. ZIPFoundation's bundled privacy manifest declares only user-selected file timestamp access and no collection.
Approved by: Release coordinator based on the release binary.
Implications: App Store Connect answer is “No, we do not collect data from this app.”

2026-09-29 — Product name risk
Value: `MacAmp` is not cleared for a public store listing.
Reason: Research found a historical commercial MacAMP audio player first released in 1997, a current namesake project, and an active historical/brand site. This is enough conflict to require the rights owner's decision or a rename.
Approved by: Release coordinator as a release blocker, not a legal determination.
Implications: Do not create the immutable App Store record or publish final artwork under this name until resolved.

2026-09-29 — Privacy policy
Value: https://github.com/h0ck3ystyx/macamp/blob/main/PRIVACY.md
Reason: The public policy matches the verified offline/no-collection release binary and returned HTTP 200 after push.
Approved by: Release coordinator based on the product implementation.
Implications: Use this URL for the App Privacy field unless a dedicated product site replaces it.

Append accepted decisions here using this format:

```text
YYYY-MM-DD — Decision name
Value:
Reason:
Approved by:
Implications:
```
