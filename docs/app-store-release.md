# Vicu App Store release preparation

Checked on October 30, 2026. Version 1.0 (build 1) was uploaded successfully to Apple at 14:47 Singapore time. TestFlight subsequently displayed the processed build with status 准备提交 (Ready to Submit), with 90-day expiry. Version 1.0 (1) was formally submitted for Apple review at 16:08 Singapore time. Apple confirmed “已提交 1 个项目”. It has not yet been approved or released.

## Account and signing

- Browser account: ACentauri Technology Limited, Team ID `NM7W76U4M4`; current role: Administrator (access upgraded during preparation).
- User confirmed ACentauri Technology Limited as the publisher on October 30, 2026.
- Initial App ID registration was denied to this Developer-role account. The administrator subsequently registered both exact IDs; they are now visible and selectable.
- Administrator access is now effective; metadata, pricing, privacy, and review details have been saved. No role change was performed by this agent.
- Project Team ID updated from `ARGMK747D8` to `NM7W76U4M4` for both the app and Live Activities extension, in Debug and Release.
- Main Bundle ID: `com.starriv.vicu`.
- Live Activities extension Bundle ID: `com.starriv.vicu.liveactivities`.
- Release version updated to `1.0`, build `1`, matching the new App Store record; iOS 18+, iPhone and iPad.
- Automatic export successfully used Cloud Managed Apple Distribution for this team and generated an IPA. Local Apple Distribution identity absence does not block cloud signing.
- App record created: **Vicu — Portfolio & Trading**, Apple ID `6828739088`, Bundle ID `com.starriv.vicu`, SKU `vicu-ios`, primary language English (US). URL: https://appstoreconnect.apple.com/apps/6828739088/distribution/info . The name Vicu alone was rejected as already in use; the user confirmed the new name.
- Publisher name used: ACentauri Technology Limited, as confirmed by the user.

## Review material and regional considerations

- User confirmed no Alpaca partnership/authorization evidence is currently available. Obtain appropriate evidence and confirm intended distribution countries before claiming authorization in review materials. Apple guidelines 3.2.1(viii) cover financial trading apps; Apple's complete-review help lists partnership documentation for financial apps. Do not claim affiliation or licensing without evidence.
- Dedicated paper API credentials were provided by the user, verified against the paper account endpoint, and saved privately to Apple review login fields with Paper-only instructions. No credential values belong in this repository.
- Privacy policy published: https://gist.github.com/starriv/a9184e0b2752f7a3c73204d5229fde1b . Anonymous raw access verified HTTP 200 and matched the local file. Support: https://github.com/starriv/vicu/issues . The user requested Issues-only public contact; review email and phone must not be published in the policy. The old website default `https://vicu.app/privacy` returned 404; use the Gist instead. In-app links added to onboarding and Settings.
- Uploaded genuine release UI captures: two iPhone 1206 × 2622 screenshots (Home, Markets) and one iPad 2064 × 2752 screenshot (Home). Apple finished processing the media before formal submission. Existing repository screenshots were not resized or reused.
- Source-audited privacy answers were published after explicit user confirmation: Other Financial Info, Search History, User ID, Purchase History, Product Interaction, Other Data; each for App Functionality, linked to identity, not tracking.
- Age rating 18+, copyright, review contact, and third-party content rights are saved. The user explicitly confirmed necessary content rights. Private review contact details remain outside repository documentation. Regional eligibility requirements still apply.
- If distributing in the EU, the account holder/admin must resolve the trader-status notice currently shown in App Store Connect.

## Saved product metadata

English (US) product metadata is saved to App Store Connect.

- Name: Vicu — Portfolio & Trading
- Primary language: English (US); the app itself also supports Simplified Chinese
- Subtitle: Your Alpaca account, on iOS
- Category: Finance
- Suggested SKU: `vicu-ios`
- Keywords: `alpaca,portfolio,stocks,orders,market,positions,investing`

### English description

Access your Alpaca brokerage account from a native iOS app.

Vicu brings your portfolio, positions, buying power, cash, and account activity into one place. Browse symbols, charts, quotes, and news. Review order history and submit market or limit orders using your own Alpaca account.

Features include:
- Portfolio and position details
- Account balances and activity
- Market search, charts, quotes, news, and options views
- Market and limit orders, with order status and history
- Order updates through Live Activities
- Light and dark appearance
- API credentials stored locally in the device-only iOS Keychain

Requires an Alpaca account and your own API credentials. Feature and market-data availability depend on your Alpaca account and permissions.

Vicu is an independent third-party client and is not affiliated with or endorsed by Alpaca. Vicu does not open brokerage accounts, hold customer funds or securities, or provide investment advice. Trading involves risk, including loss of principal.

## Official references

- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review
- https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/

## Capability audit

The current app uses its own device-only Keychain access group, local notifications, and app-updated Live Activities (`pushType: nil`). No extra portal capabilities were selected. The current code does not require APNs Push Notifications, App Groups, iCloud, Sign in with Apple, or Apple Pay. Live Activities support is already declared in the app Info.plist build settings. The portal checks In-App Purchase by default; this does not configure products or payments.

## Successful distribution export

Unsigned archive followed by `xcodebuild -exportArchive` with method `app-store-connect`, automatic signing, and team `NM7W76U4M4` succeeded. The export created `/tmp/vicu-appstore/export/vicu.ipa` with Cloud Managed Apple Distribution, store profiles for both targets, and `get-task-allow = false`. This initial export was version 0.1.0 and was not uploaded. The current 1.0 (build 1) archive includes policy links on onboarding and Settings, and passed Release archive. Upload succeeded with `/tmp/vicu-appstore/UploadOptions.plist`; successful log: `/tmp/vicu-appstore-upload-retry.log`. Apple reported “Uploaded package is processing” and “Upload succeeded”. Do not upload the older export by mistake.

## Confirmed user release preferences

- Free app; all available territories requested, subject to financial-services eligibility and EU trader-status requirements. Free pricing and availability are saved for all 175 territories.
- Public privacy/support contact: GitHub Issues only.
- Review contact supplied privately for Apple only; not published in Gist or committed in these docs.
- Policy URL and privacy answers were saved and published using effective Administrator access, with the user confirming Apple’s privacy accuracy/update statement.
- Store screenshots and verified dedicated paper review access have been provided.

## Upload validation fix

Apple initially rejected version 1.0 because iPad orientations were absent. Added the generic iPhone portrait declaration and all four iPad orientations for multitasking to both Debug and Release. Verified the resulting archive Info.plist contains `UISupportedInterfaceOrientations~ipad` with all four values, then rebuilt and successfully re-uploaded the same version/build after the rejected attempt. No devices were registered and iPad multitasking was not disabled.

## Administrator-access update

The user obtained Administrator access. Store fields are now editable. English description, promotional text, keywords, support/marketing URLs, copyright, review contact, and reviewer notes were saved. Build 1.0 (1) was associated with the version. Subtitle and Finance category were saved; age rating set to an adult 18+ override (with infrequent incidental substances/violence/weapons references possible in financial news). Public privacy-policy URL was saved. The local CLI OAuth token was not sent to Apple. The user subsequently supplied dedicated paper API credentials, which were verified and saved to review fields.

## Submission validation with Administrator access

Apple’s Add for Review check identified: missing content-rights declaration, iPad 13-inch screenshots, medium Dynamic Island iPhone screenshots, App Privacy responses, and reviewer username/password. The current local CLI paper profile uses OAuth only (API key and secret empty); its token was not disclosed to Apple. Free pricing was saved across 175 territories and availability was saved for all 175 territories as requested. The user subsequently explicitly confirmed the necessary third-party content rights; the truthful third-party-content declaration is saved.

## Simulator and screenshot validation

The unsigned simulator diagnostic build could not write the Keychain (securityd -34018). Rebuilding with simulator signing enabled and ad-hoc identity restored the application identifier/keychain entitlements; paper login and portfolio loading succeeded on both devices. The temporary inline diagnostic error label was removed. No orders were placed. Native device screenshots were uploaded through the system file chooser; no browser extension permission was expanded. All required submission checks passed after media processing; formal review submission succeeded at 16:08 Singapore time.

## Formal review submission

Apple confirmed “已提交 1 个项目” on October 30, 2026 at 16:08 Singapore time for iOS 1.0 (1). Review submission ID: `5895c048-f6d3-48a6-bf66-b89fea175475`. URL: https://appstoreconnect.apple.com/apps/6828739088/distribution/reviewsubmissions/details/5895c048-f6d3-48a6-bf66-b89fea175475 . Automatic release after approval remains selected. Submission success does not constitute review approval or confirmation of every region’s distribution eligibility.
