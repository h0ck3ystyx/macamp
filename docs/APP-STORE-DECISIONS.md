# MacAmp App Store decisions

Use this file to close the release decisions in `APP-STORE-RELEASE-PLAN.md`. A decision is final only when its status is `accepted`. Record the reason and date so a later build does not silently change store compatibility or identity.

| Decision | Proposed value | Status | Owner/action |
| --- | --- | --- | --- |
| Product name | MacAmp, subject to name and trademark clearance; identify one backup | pending | Product owner |
| Bundle identifier | Reverse-DNS identifier under a publisher-controlled domain | pending | Product owner supplies domain; release coordinator registers App ID |
| Public version | 1.0.0; increment build number for every upload | proposed | Release coordinator |
| Architectures | Universal `arm64` + `x86_64` if dependencies build and Intel QA is available; otherwise Apple silicon only | pending | Engineering feasibility and product owner scope |
| Minimum macOS | macOS 14 if the full release matrix can run there | proposed | QA must provide macOS 14 evidence |
| Business model | Free first release | proposed | Product owner |
| Territories | Broad release after required compliance is complete | pending | Product owner |
| EU trader status | Declare the publisher's actual status and verify it if required | pending | Account holder |
| Privacy posture | No accounts, ads, analytics, tracking, telemetry, or off-device data collection | proposed | Release coordinator verifies final binary |
| Support owner | Public support contact and URL | pending | Product owner |
| Privacy policy | Public policy URL matching the no-collection posture | pending | Product owner/release coordinator |
| Release method | Manual release after App Review approval | proposed | Product owner |

## Decision record

Append accepted decisions here using this format:

```text
YYYY-MM-DD — Decision name
Value:
Reason:
Approved by:
Implications:
```

