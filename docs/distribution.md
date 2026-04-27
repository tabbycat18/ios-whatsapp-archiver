# Installation and Distribution

[Back to README](../README.md)

This project is an open-source development/pre-release app. The current install
path is an Xcode developer build. GitHub provides source code, documentation,
and synthetic demo data; it does not provide universal one-tap iPhone
installation.

## Current Install Status

- The iOS viewer is intended for local development and pre-release testing.
- Developers can open the Xcode project and build the app themselves.
- There is not currently a public App Store, TestFlight, or direct GitHub IPA
  install path.
- A GitHub repository is not the same thing as a signed iPhone app
  distribution channel.

## For Personal Use On Your Own iPhone

Free Apple account builds installed from Xcode can expire after 7 days and may
need to be reinstalled from Xcode when the provisioning profile expires.

For stable personal use, the practical path is a paid Apple Developer Program
account and a properly signed build installed on your own device:

1. Open the project in Xcode:

   ```bash
   open apps/ios-archive-viewer/WhatsAppArchiveViewer.xcodeproj
   ```

2. Select your Apple developer Team in Xcode signing settings.
3. Use a unique bundle identifier that belongs to your team.
4. Build and run the app on your device.
5. Keep archive files outside the app-only container where possible, then select
   them from Files or another user-managed local storage location.
6. Do not commit personal signing, team, or provisioning settings.

Paid development and ad hoc provisioning are still time-limited. Profiles and
certificates must be renewed periodically, commonly around annual renewal
cycles for development/ad hoc workflows, depending on the profile and signing
asset type.

## For Testers

TestFlight is the recommended pre-release path for testers.

- TestFlight requires App Store Connect and TestFlight setup.
- TestFlight builds are available for up to 90 days from upload.
- External testing may require Apple's beta app review before testers can
  install the build.
- Testers should still use only their own archives and should not send private
  WhatsApp data to the project.

## For Registered-Device Testing

Ad Hoc distribution is possible with a paid Apple Developer Program account and
registered device IDs.

This can be useful for a small known tester group, but it is not suitable for
random GitHub users. The developer must manage devices, signing, provisioning,
build delivery, profile expiry, and rebuilds.

## Public Distribution Options

Possible public or semi-public distribution paths include:

- App Store distribution.
- TestFlight for pre-release testing.
- EU alternative marketplaces or Web Distribution, where available and
  eligible, subject to Apple's rules, Apple mechanisms, notarization, review,
  regional availability, and developer eligibility.

Do not claim that direct GitHub IPA installation is supported. Uploading an IPA
to GitHub is not enough to make a reliable install path for iPhone users.

## Release Checklist

Before preparing a build for testers or release, follow the
[release checklist](release-checklist.md).

## Apple References

- [Testing apps with TestFlight](https://testflight.apple.com/)
- [Provisioning profile updates](https://developer.apple.com/help/account/provisioning-profiles/provisioning-profile-updates)
- [Edit, download, or delete provisioning profiles](https://developer.apple.com/help/account/provisioning-profiles/edit-download-or-delete-profiles/)
- [Submit for Notarization](https://developer.apple.com/help/app-store-connect/managing-alternative-distribution/submit-for-notarization)
- [Getting started with Web Distribution in the EU](https://developer.apple.com/support/web-distribution-eu/)
