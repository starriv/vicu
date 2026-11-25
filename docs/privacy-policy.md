# Vicu — Privacy Policy / 隐私政策

Effective date / 生效日期: October 30, 2026 / 2026年10月30日

## English

### 1. Who we are and scope

Vicu — Portfolio & Trading (also called “Vicu”) is published by ACentauri Technology Limited (“we”, “us”). This policy explains information handling in the current Vicu iOS app and when you contact us or open our support and policy pages. Vicu is an independent client for an existing Alpaca account. We do not operate a brokerage, open brokerage accounts, hold customer assets, or provide investment advice. Alpaca operates its own services under its own terms and privacy notices.

### 2. Information the app handles

| Information | Purpose and handling |
| --- | --- |
| Alpaca API key ID, secret key, and paper/live environment | Entered by you to authenticate directly with Alpaca, test the connection, retrieve account information, and perform actions you request. Saved Alpaca credentials are stored in the iOS Keychain on your device. |
| Brokerage account information | Alpaca may return account identifiers, account status, balances, buying power, positions, order and execution details, and account activity. Vicu processes this information on your device to display your account and support trading workflows. |
| Market requests and watchlists | Symbols, searches, quote/chart/news/options requests, and watchlist changes are sent to Alpaca as needed. Alpaca may associate authenticated requests and stored watchlists with your account. |
| App settings and local state | Appearance, language, selected environment, notification preferences, optional integration settings, and event identifiers used to avoid duplicate updates are stored locally. Some local event-state keys include your Alpaca API key ID, but not the secret key. |
| Optional Logo.dev integration | Disabled by default. If you enable it and supply a Logo.dev key, requests to `img.logo.dev` include the requested ticker, that integration key, and image options. Logo.dev also receives your IP address and request metadata. The integration key is saved in the local settings database, not the Alpaca Keychain credential store. |
| Share images | Images containing the position or portfolio information you choose to share are generated on-device. Saving adds the generated image to Photos with your permission. Sharing sends it to the recipient or app you select. |
| Support messages | If you contact us, we receive the information you choose to provide, such as contact details, a problem description, and redacted attachments. Do not send API secrets, authentication codes, identity documents, or unredacted brokerage statements. |

### 3. Where information goes

The current app sends brokerage authentication and account requests directly from your device to Alpaca over HTTPS or secure WebSocket connections. We do not run an intermediary Vicu server that receives your Alpaca API secret, brokerage balances, positions, or orders as part of normal app operation. This does not mean that no information leaves your device: Alpaca receives your authenticated requests and any order instructions you submit.

When enabled, Logo.dev receives the limited request data described above; Vicu does not attach Alpaca API credentials, balances, position sizes, or order details to logo requests. A requested ticker may nevertheless reveal a security you are viewing. Images may be cached locally. Nuke and RxSwift are used for image loading and reactive operations; the current app does not integrate advertising, cross-app tracking, or third-party analytics/crash-reporting SDKs. We do not sell or rent personal information or use it for targeted advertising.

Opening a news article, support link, or this policy connects you to the relevant website. GitHub hosts our public policy/support pages and receives standard web request information, such as IP address and browser details, under its own privacy statement. User-selected sharing destinations apply their own policies. Relevant notices:

- [Alpaca disclosures and privacy notices](https://alpaca.markets/disclosures)
- [Logo.dev privacy policy](https://www.logo.dev/legal/privacy)
- [GitHub privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)

### 4. Permissions and controls

- **Device authentication:** Saved Alpaca keys use device-only iOS Keychain protection; the current default credential store requires the device to be unlocked, without a separate biometric prompt for each read or network request. iOS handles device authentication. Vicu does not receive or store your facial image or biometric template.
- **Notifications and Live Activities:** Optional notifications and Live Activities can display symbols, order status, amounts, or other account-related information on the Lock Screen or Dynamic Island. The current implementation schedules local notifications and updates Live Activities from the app; it does not use a Vicu remote-push server. Control visibility in Vicu and iOS notification/Live Activity settings.
- **Photos:** Add-only access is requested when saving a generated image. This feature does not read or upload your existing photo library. Photos may sync through your own Apple settings after you save an image.
- The current app does not request location, contacts, microphone, camera, Health data, or advertising-identifier access. The current app does not implement Vicu cloud account or iCloud settings synchronization. Device backups and third-party services are governed by your settings and their policies.

### 5. Retention, disconnection, and deletion

Saved Alpaca credentials remain in the Keychain until you use Vicu's credential-removal control for the relevant environment, or otherwise remove/revoke them. Paper and live credentials are separate: remove both if you used both. **Uninstalling the app alone may leave Keychain items behind.** Revoke or rotate API keys in Alpaca to invalidate access independently of this device.

Settings and event-state records may remain in the local app container while installed; market and image caches may remain until evicted or the app container is removed. Removing credentials clears the active connection and account display but does not promise to erase every settings/event/cache record. Clear the optional Logo.dev key and disable that integration in Settings. Deleting the app (rather than offloading it) removes its app container; manage any separate device backups yourself. Delete saved Photos images and previously shared copies separately.

Vicu does not create a separate Vicu user account. Disconnecting Vicu does not close your Alpaca account, cancel open orders, or delete Alpaca records. Contact Alpaca for brokerage-account deletion and records; financial records may be retained under applicable law. GitHub and Logo.dev retain their own records under their policies. We retain support correspondence only as needed to handle the request, maintain necessary security records, and meet applicable legal obligations; you may request deletion of support information we control.

### 6. Security and your rights

We use iOS sandboxing, device-only Keychain storage for saved Alpaca credentials, and encrypted transport to the configured services. Local settings are not a separately encrypted credential vault. No system is completely secure. Protect your device, use keys with appropriate permissions, and review shared images and Lock Screen visibility.

Where applicable law provides them, you may request access, correction, deletion, restriction, portability, or object to processing of personal information we control. You may withdraw optional permissions in iOS or disable optional integrations; this does not undo prior lawful processing or executed brokerage instructions. We may verify a request using only information reasonably needed and respond within applicable legal deadlines. We cannot remotely read or erase information held only on your device. Direct requests about Alpaca or another provider's independent records to that provider. You may also complain to your relevant data-protection authority.

Processing necessary to deliver your requested app features is undertaken to provide those features; optional permissions and integrations remain under your control. Security and support processing is limited to those purposes and applicable legal duties. Services you connect to, including Alpaca, Logo.dev, and GitHub, may process information in the United States or other countries. Their notices explain their processing and applicable transfer arrangements. Vicu's availability does not establish eligibility to open or trade through an Alpaca account in any particular country.

### 7. Children and changes

Vicu is intended for adults eligible to use the underlying brokerage services and is not directed to children. We do not knowingly solicit children's personal information. Contact us if you believe a child has provided information to us. We will update this policy when information practices change, revise the effective date, and provide additional notice or obtain consent where required.

### 8. Contact

Privacy and support contact: [Vicu project support](https://github.com/starriv/vicu/issues). Public issues are visible to others: post only a general request and never include personal financial information, API credentials, or identity documents. You can request a private follow-up channel before providing any personal details.

## 简体中文

### 1. 发布者与适用范围

Vicu — Portfolio & Trading（简称 Vicu）由 ACentauri Technology Limited 发布。本政策说明当前 iOS App 以及隐私政策、支持页面与支持沟通中的信息处理。Vicu 是独立的 Alpaca 账户客户端，不经营券商业务、不开立证券账户、不持有客户资产、不提供投资建议。Alpaca 独立提供其服务并适用其自身条款和隐私通知。

### 2. 处理的信息与用途

- **Alpaca API 凭证：**你输入的 Key ID、Secret Key 和模拟盘/实盘环境用于直接向 Alpaca 验证身份、读取账户及执行你请求的操作。保存的 Alpaca 凭证存于设备 iOS 钥匙串。
- **账户与交易信息：**包括 Alpaca 返回的账户标识、状态、余额、购买力、持仓、订单、成交和账户活动，供设备上的账户展示及交易流程使用。
- **行情与自选：**股票代码、搜索、图表、报价、新闻、期权请求及自选变更按需发送至 Alpaca；Alpaca 可将认证请求和自选记录关联至你的账户。
- **本地设置与状态：**主题、语言、交易环境、通知偏好、集成设置和防重复事件标识保存在本地。部分事件状态键含 Alpaca Key ID，不含 Secret Key。
- **可选 Logo.dev：**默认关闭。启用并提供其密钥后，会向 `img.logo.dev` 发送股票代码、Logo.dev 密钥、图片选项及正常网络请求信息（包括 IP 地址）。该集成密钥保存在本地设置数据库，不属于 Alpaca 钥匙串存储。标志请求不附带 Alpaca 凭证、余额、持仓数量或订单，但股票代码可能反映你正在查看的证券。
- **分享图片：**持仓或组合图片在本机生成；你选择保存时写入照片，选择分享时交给指定 App 或接收方。请自行检查图片中的财务信息。
- **支持沟通：**我们接收你主动发送的联系信息、问题描述和附件。不要提供 API Secret、验证码、身份证件或未经遮盖的券商账单。

### 3. 数据接收方

当前 App 通过 HTTPS 或安全 WebSocket 从设备直接连接 Alpaca，没有将 Alpaca Secret、余额、持仓和订单转发至 Vicu 中间服务器的常规流程。Alpaca 仍会收到认证请求、行情请求和你提交的交易指令。Nuke、RxSwift 用于图片与响应式处理；当前 App 未集成广告、跨 App 跟踪或第三方统计/崩溃上报 SDK。我们不出售、出租个人信息，也不使用个人信息进行定向广告。

Logo.dev 在启用时接收上述请求数据。GitHub 托管公开政策与支持页面，访问时会接收 IP 地址和浏览器等常规网站信息。打开新闻、外部链接或选择分享目标时，相应服务会按其自身政策处理信息。服务商政策见上方英文部分的官方链接。

### 4. 设备权限与展示

设备认证由 iOS 处理，Vicu 不接收人脸图像或生物识别模板。保存的 Alpaca 凭证使用仅本设备可用的钥匙串保护；当前默认实现要求设备解锁，不会为每次读取或网络请求单独弹出 Face ID。

本地通知和 Live Activities 可能在锁屏或灵动岛显示代码、订单状态、金额等账户信息；当前不使用 Vicu 远程推送服务器。你可在 App 和 iOS 中控制通知及实时活动显示。保存图片仅申请照片添加权限，不读取或上传已有照片；保存后照片可能按你的 Apple 设置同步。

当前 App 不申请定位、通讯录、麦克风、相机、健康数据或广告标识符权限，不提供独立 Vicu 云账户或 iCloud 设置同步。设备备份和第三方服务遵循你的系统设置及服务商政策。

### 5. 保存期限、断开与删除

保存的 Alpaca 凭证会保留至你通过 App 删除相应环境的凭证。模拟盘、实盘分别保存，如使用过两者请分别删除。**仅卸载 App 不保证删除钥匙串内容。**你可在 Alpaca 撤销或轮换 API 密钥，使设备外的访问权限失效。

设置、事件状态以及图片/行情缓存可在安装期间保留，缓存可能因系统或 App 清理而移除。删除凭证会清除当前连接和账户展示，但不承诺同步删除所有设置、事件或缓存记录。可在设置中清空 Logo.dev 密钥并关闭集成。删除 App（不是“卸载 App”保留数据的系统选项）会移除 App 数据容器；设备备份、已保存照片和已分享副本需另外管理。

Vicu 不创建独立用户账户。断开 Vicu 不会关闭 Alpaca 账户、取消未成交订单或删除 Alpaca 记录。证券账户及记录删除需联系 Alpaca，金融记录可能因法律义务保留。GitHub、Logo.dev 按各自政策保留其记录。我们仅在处理支持请求、必要安全及法律义务所需期间保存支持信息，你可请求删除我们控制的支持信息。

### 6. 安全、权利与跨境处理

我们使用 iOS 沙盒、Alpaca 凭证的设备专用钥匙串和加密传输。本地设置不是单独加密的凭证保险库，任何系统均无法保证绝对安全。请保护设备并检查分享内容和锁屏显示。

根据适用法律，你可以请求访问、更正、删除、限制、迁移我们控制的个人信息或对处理提出异议；可撤回可选系统权限或关闭集成，但这不会撤销已合法发生的处理或交易指令。我们可在必要范围内验证请求并依法答复，无法远程读取或删除仅在设备上的数据。独立服务商控制的数据应向该服务商申请，你也可向有管辖权的数据保护机构投诉。

必要处理用于实现你请求的功能；可选权限与集成由你控制。安全和支持处理限于相应目的及适用法律义务。Alpaca、Logo.dev、GitHub 可能在美国或其他国家处理信息，其隐私通知说明相应跨境安排。App 可以下载不代表你在所在地具备开立或交易 Alpaca 账户的资格。

### 7. 儿童、政策更新与联系

Vicu 面向有资格使用相关券商服务的成年人，不针对儿童，也不主动征集儿童个人信息。若你认为儿童向我们提供了信息，请联系我们。信息处理发生变化时，我们会更新政策及日期，并在要求时另行通知或取得同意。

隐私与支持渠道：[Vicu 项目支持](https://github.com/starriv/vicu/issues)。公开 Issue 可被其他人查看，请仅发布概括性请求，不要包含个人财务信息、API 凭证或证件；提供个人详情前可先申请私下跟进渠道。
