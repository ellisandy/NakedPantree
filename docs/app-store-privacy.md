# App Store Privacy — Naked Pantree

> Source-of-truth answers for the App Privacy ("nutrition label")
> questionnaire in App Store Connect, the App Tracking Transparency
> declaration, and the privacy-required-reasons API manifest.
>
> Every answer below is grounded in either a code path
> (`file:line`) or a primary-source Apple URL — no folklore.

The TL;DR for the submitter:

- **"Data Collected" = NO.** Per Apple's strict definition (see §0
  below), Naked Pantree does not collect data. All user data lives in
  the user's own iCloud private database, sharing is brokered by
  Apple's CloudKit between consenting iCloud accounts, and we operate
  no backend that can read it.
- **Privacy Policy URL = optional.** Apple requires one only when
  data is "Collected." We are not, so the field can be left blank.
  Recommendation: ship one anyway as a small good-citizen gesture
  (host `PRIVACY.md` on GitHub Pages or link the repo's copy). Not a
  blocker.
- **App Tracking Transparency (ATT) = not needed.** Zero third-party
  SDKs, zero ad networks, zero cross-app/cross-site tracking. The ATT
  prompt is not shown and the questionnaire is answered "Not used to
  Track."
- **`PrivacyInfo.xcprivacy` = needed (follow-up).** We use
  `UserDefaults` (a "Required Reason" API). No `PrivacyInfo.xcprivacy`
  exists in the repo today. See §5 — flagged as a follow-up code-side
  task; deliberately not shipped in this doc-only PR.

---

## 0. Apple's definition of "Collect"

Apple Developer — *App Privacy Details*
(https://developer.apple.com/app-store/app-privacy-details/):

> "Collect" refers to transmitting data off the device in a way that
> allows you and/or your third-party partners to access it for a
> period longer than what is necessary to service the transmitted
> request in real time.

The same page enumerates exclusions that explicitly do **not** count
as collection — including data that "is not used for tracking
purposes, meaning the data is not linked with third-party data for
advertising purposes or shared with a data broker." It also states:

> Data sent off the device must be encrypted in transit, and you must
> have a published privacy policy that … describes your use of this
> data … However, you don't need to disclose data … [if] the data is
> provided by the user in the app's interface, it's clear to the user
> what data is collected, the user's name or account name is
> prominently displayed in the submission form alongside the other
> data elements being submitted, and the user affirmatively chooses
> to provide the data for collection each time.

Additionally, Apple's developer documentation on iCloud / CloudKit
makes the trust model explicit. CloudKit private database records
are stored in the user's own iCloud account; the app developer
cannot read them. (See *CloudKit Overview*,
https://developer.apple.com/icloud/cloudkit/, and the "Private
database" entry in the *CKDatabase* reference.) The same is true of
CloudKit shares: data flows between consenting iCloud accounts, but
it remains inside Apple's CloudKit infrastructure and is not visible
to us.

**Therefore: Naked Pantree does not "Collect" data within Apple's
meaning.** All four conditions hold:

1. The only off-device transmission is to the user's own CloudKit
   private database (and, for shared households, to consenting
   recipients' iCloud accounts via CloudKit). No data is transmitted
   to a server we operate.
2. We have no backend, no analytics SDK, no telemetry pipeline, no
   crash reporter that exfiltrates data, and no third-party SDK that
   does any of the above. (See §1 verification.)
3. We are not "accessing it for a period longer than necessary to
   service the request" — we have no access to it at all. The user
   is the only party who can read the data; we are unable to.
4. None of the data is used for tracking, linked with third-party
   data, or shared with data brokers.

This is the same posture Apple's own apps (Notes, Reminders, etc.)
declare on the App Store and the same answer Apple's WWDC 2020
session "Build Trust Through Better Privacy" (Session 10676) used as
its illustrative example for "data not collected."

---

## 1. Verification: no third-party network calls

Confirmed with a tree-wide grep. None of the following symbols appear
in `NakedPantreeApp/**` or `Packages/**`:

- `URLSession`, `URLRequest`
- `Analytics`, `Crashlytics`, `Firebase`, `Sentry`, `Mixpanel`,
  `Amplitude`, `Segment`

Source-of-truth check — the iOS app target's only external
dependencies are:

- `Packages/Core` (local SwiftPM package, in this repo).
  See `project.yml` (`packages: Core: path: Packages/Core`) and
  `Packages/Core/Package.swift` (zero external `dependencies`).

No CocoaPods/Carthage manifests exist; no other SwiftPM remote
packages are declared. The only network surface used by the app
is CloudKit (Apple's framework, not third-party) via
`NSPersistentCloudKitContainer` and direct `CKContainer`/`CKShare`
calls — both flow into the user's own iCloud account.

---

## 2. Data Inventory

For each datum the app reads, writes, or transmits: which of Apple's
14 questionnaire categories it falls into, whether it is *Collected*
(per §0), whether it is *Linked to identity*, and whether it is
*Used to Track*.

| # | Datum | Apple category | Stored where | Transmitted where | Collected? | Linked to identity? | Used to Track? | Code citation |
|---|---|---|---|---|---|---|---|---|
| 1 | Item name (`Item.name`) | User Content → Other User Content | Core Data + user's CloudKit private/shared DB | User's iCloud only | No (§0) | No | No | `Packages/Core/Sources/NakedPantreeDomain/Entities.swift:52` |
| 2 | Item quantity / unit (`Item.quantity`, `Item.unit`) | User Content → Other User Content | Same as above | User's iCloud only | No | No | No | `Entities.swift:53–54` |
| 3 | Item expiry / notes (`Item.expiresAt`, `Item.notes`) | User Content → Other User Content | Same | User's iCloud only | No | No | No | `Entities.swift:55–56` |
| 4 | Location name + kind (`Location.name`, `Location.kind`) | User Content → Other User Content | Same | User's iCloud only | No | No | No | `Entities.swift:25–27` |
| 5 | Household name (`Household.name`) | User Content → Other User Content | Same | User's iCloud only | No | No | No | `Entities.swift:10` |
| 6 | Item photos (`ItemPhoto.imageData`, `ItemPhoto.thumbnailData`) | User Content → Photos or Videos | Same (full asset promoted to `CKAsset`) | User's iCloud only | No | No | No | `Entities.swift:89–90`; `ARCHITECTURE.md` §9 |
| 7 | Photo caption (`ItemPhoto.caption`) | User Content → Other User Content | Same | User's iCloud only | No | No | No | `Entities.swift:91` |
| 8 | Notification reminder time (`hourOfDay`, `minute`) | (none — preference, not transmitted) | `UserDefaults` on-device only | Not transmitted | No | No | No | `NakedPantreeApp/Notifications/NotificationSettings.swift:36–49,61–62,94–105` |
| 9 | Camera capture (live frames) | (none — never persisted as such) | Not stored; `UIImage` is converted, resized, and stored as #6 | Same as #6 (user's iCloud only) | No | No | No | `NakedPantreeApp/Photos/PhotoCaptureSheet.swift:24–32`; `Info.plist` `NSCameraUsageDescription` |
| 10 | Photo library selection (single-image picker, user-selected only) | User Content → Photos or Videos (covered by #6) | Same as #6 | Same as #6 | No | No | No | `NakedPantreeApp/Features/Items/ItemDetailView.swift:16,72,81–82,270`; `PhotosPicker` |
| 11 | iCloud account identity (whether the user is signed in; `CKAccountStatus`) | (none — read-only Apple system state) | Not stored | Not transmitted | No | No | No | `NakedPantreeApp/App/AccountStatusMonitor.swift:52,66` |
| 12 | CloudKit share metadata (`CKShare`, share invite acceptance) | (none — Apple system flow) | Stored by CloudKit, not the app | Apple iCloud (between consenting accounts) | No | No | No | `NakedPantreeApp/App/NakedPantreeAppDelegate.swift:45`; `NakedPantreeApp/Sharing/CloudSharingControllerView.swift` |
| 13 | Local-notification scheduling identifiers | (none — on-device only) | `UNUserNotificationCenter` on-device queue | Not transmitted | No | No | No | `NakedPantreeApp/App/NakedPantreeAppDelegate.swift:39`; `ARCHITECTURE.md` §8 |

### Photos: why "User-selected only"

`PhotosPicker` (SwiftUI / PhotosUI) and `UIImagePickerController` with
`.camera` source both operate without `Photo Library Usage`
permission — `PhotosPicker` is the Apple-supplied "limited library"
picker that gives the app only the user's chosen items, and the
camera path captures a single shot. We have **no**
`NSPhotoLibraryUsageDescription` or `NSPhotoLibraryAddUsageDescription`
key in `Info.plist`, only `NSCameraUsageDescription`
(`NakedPantreeApp/Resources/Info.plist:23–24`). The photo library is
never read in bulk and the app cannot enumerate a user's photos.

### CloudKit: why it isn't "Collected"

The app target's `NakedPantree.entitlements`
(`com.apple.developer.icloud-services: CloudKit`,
`com.apple.developer.icloud-container-identifiers:
iCloud.cc.mnmlst.nakedpantree`) places all records in the **user's
own** iCloud private database. Apple's CKDatabase reference makes
the trust model explicit: private-database records are accessible
only to the iCloud-account holder; the app developer cannot read
them. CloudKit Sharing extends that to consenting recipients of a
`CKShare`. There is no developer-side server, no developer-side
analytics, no developer-side log of record content. This is the
canonical Apple-blessed architecture for "iCloud sync without
collecting user data."

---

## 3. App Privacy questionnaire — proposed answers

These follow App Store Connect's exact question wording (Apple
Developer — *App Privacy Details on the App Store*,
https://developer.apple.com/app-store/app-privacy-details/). Apple
asks the same questionnaire path multiple times under different
conditional branches; each numbered entry below is one question
with its proposed answer and a one-line justification.

1. **Q: Do you or your third-party partners collect data from this
   app?**
   **A: No.**
   *Justification:* Per §0, the app stores all user data in the
   user's own CloudKit private database and shares it only with
   consenting iCloud accounts via CloudKit. We have no backend, no
   analytics SDK, no third-party SDK of any kind. (Verified by tree
   grep — see §1; `Packages/Core/Package.swift` declares zero
   external dependencies.)

   > Selecting "No" here closes out the questionnaire — Apple does
   > not ask the per-category, per-purpose, or per-tracking questions
   > below. They are still answered explicitly here so the team has a
   > defensible record if Apple's review team queries the
   > declaration, or if a future change (analytics, crash reporter)
   > would flip the headline answer.

2. **Q: Contact Info (Name, Email, Phone, Address, Other Contact
   Info) — collected?**
   **A: Not Collected.**
   *Justification:* No field on `Household`/`Location`/`Item`/
   `ItemPhoto` is contact info (`Entities.swift:8–112`). The app
   never asks for the user's name, email, phone, or address; iCloud
   identity is brokered by Apple via `CKContainer`
   (`AccountStatusMonitor.swift:52,66`) and is never read or stored
   by the app.

3. **Q: Health & Fitness — collected?**
   **A: Not Collected.**
   *Justification:* No HealthKit entitlement; no health-related
   field in the domain model.

4. **Q: Financial Info — collected?**
   **A: Not Collected.**
   *Justification:* No purchases, no payments, no Apple Pay, no
   StoreKit usage in the app target.

5. **Q: Location (Precise / Coarse) — collected?**
   **A: Not Collected.**
   *Justification:* `Location` in our domain is a *physical
   storage location* (a pantry shelf, a garage freezer) named by the
   user — see `Entities.swift:22–45` and `ARCHITECTURE.md` §4. We do
   not link `CoreLocation`, request `NSLocationWhenInUseUsageDescription`,
   or read GPS in any form.

6. **Q: Sensitive Info (race, religion, sexual orientation, …) —
   collected?**
   **A: Not Collected.**
   *Justification:* No such fields exist in the domain model
   (`Entities.swift`). User-typed item names and notes are free-form,
   so a user could in principle type sensitive content into them, but
   the data still never leaves the user's iCloud — see Apple's
   *App Privacy Details* exception for data the user types into a
   surface where the data's purpose is obvious to them.

7. **Q: Contacts — collected?**
   **A: Not Collected.**
   *Justification:* No `Contacts.framework` import; no
   `NSContactsUsageDescription` in `Info.plist`.

8. **Q: User Content — Photos or Videos, Audio, Gameplay, Customer
   Support, Other User Content — collected?**
   **A: Not Collected.**
   *Justification:* Items, locations, photos, captions, and notes
   *are* user content (`Entities.swift`), but per §0 they are stored
   in the user's CloudKit private/shared database, not collected by
   us. Photos use `PhotosPicker` (user-selected only,
   `ItemDetailView.swift:16,82`) and `UIImagePickerController` with
   `.camera` source (`PhotoCaptureSheet.swift:24–26`); never the
   full library, never video.

9. **Q: Browsing History — collected?**
   **A: Not Collected.**
   *Justification:* No web view, no in-app browser. The app does
   not record what users view.

10. **Q: Search History — collected?**
    **A: Not Collected.**
    *Justification:* The sidebar search field
    (`ARCHITECTURE.md` §7, "Search is a peer content-column mode")
    runs an in-memory `NSPredicate` against the local Core Data
    store. No query string is logged, persisted, or transmitted.

11. **Q: Identifiers (User ID, Device ID) — collected?**
    **A: Not Collected.**
    *Justification:* The app uses no `IDFA`, no `IDFV`, no
    `identifierForVendor`, no advertising identifier. iCloud
    account identity is brokered by Apple's `CKContainer`
    (`AccountStatusMonitor.swift:52`) and is invisible to the app —
    we receive only an `accountStatus` enum (`available`,
    `noAccount`, etc.), not a user identifier.

12. **Q: Purchases — collected?**
    **A: Not Collected.**
    *Justification:* No StoreKit, no IAP, no subscription. The app
    is paid-up-front (or whatever the App Store listing chooses)
    and has no purchase history surface.

13. **Q: Usage Data (Product Interaction, Advertising Data, Other
    Usage Data) — collected?**
    **A: Not Collected.**
    *Justification:* No analytics SDK, no event-logging pipeline,
    no advertising integration. Verified by §1 grep.

14. **Q: Diagnostics (Crash Data, Performance Data, Other
    Diagnostic Data) — collected?**
    **A: Not Collected.**
    *Justification:* We do not opt into Apple's
    "Improve and Personalize" analytics on the developer side
    (Xcode Organizer's automatic crash + metric reports stay with
    Apple, do not flow through us). We ship no third-party crash
    reporter (Crashlytics, Sentry, Bugsnag, etc.) — see §1.

15. **Q: Other Data — collected?**
    **A: Not Collected.**
    *Justification:* Nothing left over.

16. **Q: Is data linked to the user's identity?**
    **A: N/A — no data is collected.**
    *Justification:* Closed out by Q1.

17. **Q: Is data used to track the user (per ATT definition)?**
    **A: No.**
    *Justification:* No tracking SDK, no ad network, no shared data
    broker, no cross-app/cross-site linkage. See §4.

---

## 4. App Tracking Transparency (ATT)

Apple Developer — *User Privacy and Data Use*
(https://developer.apple.com/app-store/user-privacy-and-data-use/):

> "Tracking" refers to the act of linking user or device data
> collected from your app with user or device data collected from
> other companies' apps, websites, or offline properties for targeted
> advertising or advertising measurement purposes. Tracking also
> refers to sharing user or device data with data brokers.

Naked Pantree does none of this:

- No third-party SDKs (verified §1).
- No advertising integration.
- No data sharing with data brokers.
- No `NSUserTrackingUsageDescription` key in `Info.plist`
  (`NakedPantreeApp/Resources/Info.plist`).
- No call to `ATTrackingManager.requestTrackingAuthorization`
  anywhere in the codebase.

**We do not need to present the ATT prompt.** In the App Privacy
questionnaire, "Used to Track You" is answered **No** for every
category. We answer "No" to the standalone tracking question (Q17
above).

---

## 5. Privacy-required-reasons API declarations
### (`PrivacyInfo.xcprivacy`)

Apple Developer — *Describing use of required reason API*
(https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api).
Apple requires apps to declare which "Required Reason" APIs they
use, with an approved reason code, in a `PrivacyInfo.xcprivacy`
manifest. The four families Apple currently enumerates are:

1. `NSPrivacyAccessedAPICategoryFileTimestamp` — file timestamp APIs
   (`creationDate`, `modificationDate`, `getattrlist`, `stat`, etc.)
2. `NSPrivacyAccessedAPICategorySystemBootTime` —
   `systemUptime`, `mach_absolute_time`, `clock_gettime` with
   monotonic clocks.
3. `NSPrivacyAccessedAPICategoryDiskSpace` — `volumeAvailableCapacity`,
   `NSURLVolumeAvailableCapacityKey`, etc.
4. `NSPrivacyAccessedAPICategoryActiveKeyboards` — input mode lookup.
5. `NSPrivacyAccessedAPICategoryUserDefaults` — `UserDefaults` /
   `NSUserDefaults` reads and writes.

Tree-wide grep result:

| API category | Used? | Where |
|---|---|---|
| File timestamp | No | No `creationDate`/`modificationDate`/`getattrlist`/`stat` calls. |
| System boot time | No | No `systemUptime`/`mach_absolute_time`/`clock_gettime` calls. |
| Disk space | No | No `volumeAvailableCapacity`/`NSURLVolumeAvailableCapacityKey` calls. |
| Active keyboards | No | No active-input-mode lookups. |
| **`UserDefaults`** | **Yes** | `NakedPantreeApp/Notifications/NotificationSettings.swift:36–49,55,94–105` — reads and writes the per-device notification reminder time. SwiftUI's `@AppStorage` is not used (verified — zero matches). |

The `ProcessInfo.processInfo.environment` lookups in
`NakedPantreeApp/App/NakedPantreeApp.swift:39,50` and
`NakedPantreeApp/App/SnapshotFixtures.swift:24,183,212` are
**environment-variable** reads (test/preview hooks), not
`processInfo.systemUptime` — they are not in any required-reason
category.

### Recommended `PrivacyInfo.xcprivacy` content (FOLLOW-UP)

The repo does **not** currently contain a `PrivacyInfo.xcprivacy`
file (verified — `find -name "*.xcprivacy"` returned zero results).
Per Apple's guidance, apps using `UserDefaults` must declare it.
**This is a code-side gap**; per Phase 11.1b scope it is flagged
here as a follow-up, not fixed in this PR.

The `PrivacyInfo.xcprivacy` plist that the code-side follow-up
should ship is roughly:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- We do not collect any data, do not track, and do not link
         data to identity (see docs/app-store-privacy.md). -->
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>

    <!-- Required-reason APIs in use. -->
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <!-- "CA92.1" — Access info from same app, per Apple's approved reasons. -->
                <string>CA92.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

The reason code `CA92.1` ("Declare this reason to access user
defaults to read and write information that is only accessible to
the app itself") matches our usage exactly: `NotificationSettings`
reads its own `settings.notifications.reminderHour` /
`settings.notifications.reminderMinute` keys
(`NotificationSettings.swift:61–62`) and writes them back —
strictly first-party, strictly app-internal.

The follow-up task is straightforward: add a
`PrivacyInfo.xcprivacy` resource to `NakedPantreeApp/Resources/`,
wire it into `project.yml` under the `NakedPantree` target's
`resources:` list, and `xcodegen` to regenerate. No code changes.

---

## 6. Privacy Policy URL

Apple Developer — *App Store Review Guidelines* §5.1.1:

> Apps that collect user or usage data must … provide access to
> information about how and where the data will be used. Data
> collected from apps may only be shared with third parties to
> improve the app or serve advertising (in compliance with the Apple
> Developer Program License Agreement). … Data collected from apps
> must not be used to enable targeted ads.

App Store Connect requires a **Privacy Policy URL** for any app
whose App Privacy answer is "Data Collected = Yes," and for any app
that uses Sign in with Apple, ATT, or specific data categories. We
trigger none of those. **The Privacy Policy URL field can be left
blank** for the App Privacy section.

That said, App Review still surfaces the field (and some users look
for it). A trivial privacy policy is good citizenship and removes a
plausible reviewer-friction point. **Recommended path** — pick one
of:

1. **Repo-hosted, plain Markdown.** Add `PRIVACY.md` to the repo
   root with a one-page statement that mirrors §0 of this doc:
   "Naked Pantree stores all your data in your own iCloud account.
   We have no servers, no analytics, no tracking. The app developer
   cannot read your inventory, your photos, or your shared
   households." Link to the GitHub raw URL or the rendered URL.
   Lowest cost, scales fine for a first release.
2. **GitHub Pages site.** Same content, prettier URL
   (`https://ellisandy.github.io/NakedPantree/privacy`). One-time
   setup of `gh-pages` or `/docs` Pages. Worth it before public
   launch; not worth blocking TestFlight on.
3. **Custom domain.** Overkill for v1.0.

Recommendation: ship option 1 alongside the App Store submission,
upgrade to option 2 before the public marketing site exists. Either
way, **TestFlight does not require this** — it is needed for the
public App Store listing only.

---

## 7. Summary of recommendations for the submitter

| Field | Answer | Source |
|---|---|---|
| App Privacy → Data Collected | No | §0, §3 Q1 |
| App Privacy → all 14 categories | Not Collected | §3 Q2–Q15 |
| Linked to Identity | N/A | §3 Q16 |
| Used to Track | No | §3 Q17, §4 |
| ATT prompt | Not used | §4 |
| Privacy Policy URL | Optional; ship a `PRIVACY.md` anyway | §6 |
| `PrivacyInfo.xcprivacy` | **Required** — ship in code-side follow-up | §5 |
| `NSUserTrackingUsageDescription` in Info.plist | Do not add | §4 |
| `NSPhotoLibraryUsageDescription` in Info.plist | Do not add (PhotosPicker covers it) | §2 "Photos" |

---

## 8. Follow-ups flagged from this exercise

1. **Add `PrivacyInfo.xcprivacy`** declaring `UserDefaults` usage
   with reason code `CA92.1`, plus the empty-array
   `NSPrivacyCollectedDataTypes` and `NSPrivacyTrackingDomains`
   declarations. Wire into `project.yml`. (See §5.) Tracked
   separately — not in scope for this doc-only PR.
2. **Ship a `PRIVACY.md`** in the repo root. (See §6.) Optional;
   recommended before public-App-Store submission, not required for
   TestFlight.
