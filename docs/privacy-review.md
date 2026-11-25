# Vicu privacy release review

Reviewed current source on October 30, 2026.

Public policy: https://gist.github.com/starriv/a9184e0b2752f7a3c73204d5229fde1b

| Area | Source evidence | Disclosure |
| --- | --- | --- |
| Alpaca credentials | Services/Credentials/CredentialStore.swift; Services/API/APIPaths.swift | Device-only Keychain; direct authenticated Alpaca HTTPS/WSS; paper/live separately stored |
| Authentication | Services/App/AppServices.swift; CredentialStore default initializer | Default store is when-unlocked device-only; no separate Face ID prompt per read; do not advertise implemented biometric gating |
| Account, trading and watchlists | Services/Alpaca; App/AppModel | Account and financial data on-device; authenticated requests, orders and watchlist updates sent to Alpaca |
| Configuration and events | Services/Configuration; Services/Persistence/SQLiteDatabase.swift | Local SQLite settings and event state; some state keys include API key ID; cloud-named configuration layer is local SQLite, not iCloud sync |
| Logo.dev | DesignSystem/Components/SymbolLogoView.swift; AppConfigurationKeys.Integrations | Optional, disabled by default; ticker and integration key in HTTPS request, provider IP/request logging; key is in local configuration |
| Image cache | DesignSystem/AppImagePipeline.swift | Nuke memory and disk cache; no analytics SDK in dependency list |
| Photos and sharing | Features/AssetDetail/AssetShareSupport.swift | On-device generated images; Photos add-only permission; user-selected share recipient |
| Notifications | Services/Notifications; Services/LiveActivities | Local notification content and app-updated Live Activities can expose account details on Lock Screen |
| Retention and deletion | AppModel+Credentials.clearCredentials; CredentialStore.delete | Credential removal is per environment; not a full settings/cache wipe; Keychain may survive uninstall; revoke keys at Alpaca |
| Public support and policy | GitHub Issues and Gist | Website request data and public issue contents; user chose Issues-only contact; private review contacts excluded |

## Before submission

- App Store privacy answers must include applicable third-party practices. Do not infer “Data Not Collected” solely from the app privacy manifest or the absence of Vicu servers. Resolve categories and linkage for authenticated financial requests and optional Logo.dev request logging against Apple definitions and provider policies.
- No Vicu account creation exists; credential removal is not Alpaca account deletion. Do not promise that uninstall deletes Keychain items or cancels orders.
- Access to the policy is provided before credentials are entered and in Settings.
- The policy describes current behavior; it does not establish Alpaca authorization, licensing, or worldwide financial-service eligibility.
- No runtime UI interaction or live brokerage trading was exercised as part of the policy-link change; Release archive is the compile verification. Review credentials and screenshots still need preparation.

## References

- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/app-store/app-privacy-details/
- https://www.logo.dev/legal/privacy
- https://alpaca.markets/disclosures
