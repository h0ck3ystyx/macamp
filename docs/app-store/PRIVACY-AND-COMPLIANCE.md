# Privacy and compliance answers — MioAmp 1.0

These answers describe the current release binary and must be rechecked if code or dependencies change.

## App Privacy

- Data collection: **No, we do not collect data from this app.**
- Tracking: **No.**
- Privacy policy URL: **https://github.com/h0ck3ystyx/mioamp/blob/main/PRIVACY.md** (public and HTTP 200 verified September 29, 2026 after the repository rename).
- Privacy choices URL: omit; the app does not maintain an off-device account or data record.

Evidence: the app contains no network entitlement, network client, analytics, ads, telemetry, sign-in, or upload implementation. Its privacy manifest declares no tracking, collected-data types, tracking domains, or required-reason API use. User-selected files and preferences remain on device.

## Encryption and export compliance

- `ITSAppUsesNonExemptEncryption`: **No (`false`).**
- Rationale: MioAmp does not implement or bundle encryption. It uses no network service. Apple platform security around the sandbox, code signing, file storage, and App Store delivery is operating-system functionality rather than app-provided non-exempt encryption.

## Content rights

- The app does not contain, access, display, or stream third-party catalog content.
- Users choose their own local audio and are responsible for rights to it.
- Bundled skins and icon artwork are original project assets.
- Store screenshots must use generated or explicitly licensed audio names and artwork.
- ZIPFoundation and the vendored dr_libs decoders are covered in `THIRD-PARTY-NOTICES.md`, which is included in the bundle.

## Age rating questionnaire

Answer **None/No** for user-generated content, messaging/chat, advertising, web access, parental controls, age assurance, unrestricted web access, loot boxes, gambling, contests, violence, sexual content, profanity, horror, alcohol/tobacco/drugs, and medical/wellness content. Choose **Not Applicable** for Made for Kids and rating override. App Store Connect calculates the final regional ratings.

## Business and distribution

- Price: Free.
- In-app purchases/subscriptions: None.
- Accounts/login: None.
- Release: Manual after App Review approval.
- Territories: requires the account holder's selection.
- EU DSA: account holder must declare actual trader status even if the EU is excluded. A trader distributing in the EU must provide verified public address, phone, and email details.
- Agreements/tax/banking: confirm in App Store Connect. A free app generally avoids paid-app banking and pricing setup, but current program agreements must still be accepted.

## Primary Apple references checked September 29, 2026

- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- App privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- Age rating: https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating
- EU DSA: https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements
- Upload builds: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds
