# Naked Pantree — Privacy Policy

**Effective:** 28 April 2026

## Summary

Naked Pantree does not collect, store, or transmit any of your data to
servers we operate. There are no analytics, no tracking, no third-party
SDKs, and no advertising. Everything you put into the app lives in
**your own iCloud account** — the developer cannot read it.

## What we collect

**Nothing.** We have no servers and no analytics pipeline. The app
runs entirely on your device, with optional sync through Apple's
iCloud service. We never receive a copy of your inventory, your
photos, your shared households, or any other data you enter.

## Where your data lives

Naked Pantree stores everything you enter — items, locations,
households, photos, captions, expiry dates, notes — in **your own
iCloud account's private database**, using Apple's CloudKit framework.
Apple's documentation describes the trust model: data in a private
CloudKit database is accessible only to the iCloud account holder,
and the app developer cannot read it.

If you sign out of iCloud, the app continues to work with on-device
storage only. No data is sent anywhere.

## Sharing households

If you invite a partner, roommate, or family member to a shared
household, Apple's CloudKit Sharing routes the invite between iCloud
accounts. Only the people you invite can see the shared inventory.
We are not a party to that exchange — the invite, the shared records,
and the access control are handled by Apple inside iCloud, not by us.

## Photos

When you attach a photo to an item, Naked Pantree resizes it on your
device and stores the result alongside the item in your iCloud
private database (or shared database, if the item belongs to a shared
household). The app does not read your full photo library — it only
sees the single image you choose, via Apple's photo picker.

The app requests camera access (for taking new photos) but does not
request photo-library access — Apple's user-controlled photo picker
covers that flow without granting the app blanket library access.

## Notifications

If you enable expiry-reminder notifications, the app schedules **local
notifications** through `UNUserNotificationCenter` on your device.
Local notifications run entirely on-device — Apple's push servers are
not involved, and no data is sent off the device.

The app stores your preferred reminder time (hour and minute) in
`UserDefaults` on the device only. This preference does not sync and
is not transmitted anywhere.

## Tracking

Naked Pantree does **not** track you. Specifically:

- No third-party SDKs of any kind.
- No advertising integrations.
- No data shared with data brokers.
- No use of the IDFA (advertising identifier).
- No App Tracking Transparency prompt — the app never asks because
  tracking does not happen.
- No cross-app or cross-website linkage.

In Apple's App Privacy nutrition label terms: **Data Not Collected**,
**Not Used to Track You**.

## Children's privacy

Naked Pantree is rated 4+ and is suitable for all ages. The app does
not collect any data from anyone, including children. No accounts,
no profiles, no contact details.

## Third parties

The only third party involved in the app's operation is **Apple** —
specifically, Apple's iCloud / CloudKit service. Apple's privacy
policy applies to data stored in your iCloud account:
<https://www.apple.com/legal/privacy/>.

We use no other third-party services.

## Changes to this policy

If the privacy posture of the app ever changes — for example, if a
future version adds analytics, crash reporting, or any other data
flow that leaves your device — this policy will be updated and the
**Effective** date at the top will change. We will not silently
expand data collection.

## Contact

Questions, concerns, or corrections:

**Andrew (Jack) Ellis**
Email: <jack@mnmlst.cc>
GitHub: <https://github.com/ellisandy/NakedPantree>

---

*This policy describes the v1.0 release of Naked Pantree. The
internal source-of-truth document with code citations and
questionnaire answers is `docs/app-store-privacy.md` in the
repository.*
