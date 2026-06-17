# Vicu

![Platform](https://img.shields.io/badge/platform-iOS%2018%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![UI](https://img.shields.io/badge/SwiftUI-Liquid%20Glass-7d4bff)

A native iOS client for your Alpaca brokerage account, built in SwiftUI.

一款为 Alpaca 证券开发的非官方 iOS 客户端, 设计精美, 功能完善.

>Vicu is named after the vicuña, a close relative of the alpaca.

>Vicu 取意于 vicuña，一种与 alpaca 亲缘相近的南美驼科动物.

English | [简体中文](#简体中文)
---

## Screenshots / 截图

Light and dark, side by side. / 浅色与深色对照。

### Home / 首页

| Light | Dark |
|:---:|:---:|
| <img src="docs/screenshots/light/home-1.png" width="250" alt="Home — Light"> | <img src="docs/screenshots/dark/home-1.png" width="250" alt="Home — Dark"> |
| <img src="docs/screenshots/light/home-2.png" width="250" alt="Home detail — Light"> | <img src="docs/screenshots/dark/home-2.png" width="250" alt="Home detail — Dark"> |

### Markets / 行情

| Light | Dark |
|:---:|:---:|
| <img src="docs/screenshots/light/markets.png" width="250" alt="Markets — Light"> | <img src="docs/screenshots/dark/markets.png" width="250" alt="Markets — Dark"> |
| <img src="docs/screenshots/light/search.png" width="250" alt="Search — Light"> | <img src="docs/screenshots/dark/search.png" width="250" alt="Search — Dark"> |

### Orders / 订单

| Light | Dark |
|:---:|:---:|
| <img src="docs/screenshots/light/order-list.png" width="250" alt="Orders — Light"> | <img src="docs/screenshots/dark/order-list.png" width="250" alt="Orders — Dark"> |
| <img src="docs/screenshots/light/cancel-order.png" width="250" alt="Cancel order — Light"> | <img src="docs/screenshots/dark/cancel-order.png" width="250" alt="Cancel order — Dark"> |

### Position / 持仓

| Light | Dark |
|:---:|:---:|
| <img src="docs/screenshots/light/position.png" width="250" alt="Position — Light"> | <img src="docs/screenshots/dark/position.png" width="250" alt="Position — Dark"> |
| <img src="docs/screenshots/light/share.png" width="250" alt="Share position — Light"> | <img src="docs/screenshots/dark/share.png" width="250" alt="Share position — Dark"> |

### Trade / 交易

| Light | Dark |
|:---:|:---:|
| <img src="docs/screenshots/light/trad-1.png" width="250" alt="Trade — Light"> | <img src="docs/screenshots/dark/trad-1.png" width="250" alt="Trade — Dark"> |
| <img src="docs/screenshots/light/trade-2.png" width="250" alt="Trade detail — Light"> | <img src="docs/screenshots/dark/trade-2.png" width="250" alt="Trade detail — Dark"> |
| <img src="docs/screenshots/light/trade-market-order.png" width="250" alt="Market order — Light"> | <img src="docs/screenshots/dark/trade-market-order.png" width="250" alt="Market order — Dark"> |
| <img src="docs/screenshots/light/trade-limit-order.png" width="250" alt="Limit order — Light"> | <img src="docs/screenshots/dark/trade-limit-order.png" width="250" alt="Limit order — Dark"> |

### More / 更多

Asset detail, options & account setup. / 资产详情、期权与账户配置。

| Light | Dark |
|:---:|:---:|
| <img src="docs/screenshots/light/news.png" width="250" alt="News — Light"> | <img src="docs/screenshots/dark/news.png" width="250" alt="News — Dark"> |
| <img src="docs/screenshots/light/options.png" width="250" alt="Options — Light"> | <img src="docs/screenshots/dark/options.png" width="250" alt="Options — Dark"> |
| <img src="docs/screenshots/light/alpaca-acct-config.png" width="250" alt="Account setup — Light"> | <img src="docs/screenshots/dark/alpaca-acct-config.png" width="250" alt="Account setup — Dark"> |

---

## English

Vicu is a native iOS app for your Alpaca brokerage account. It's written entirely in SwiftUI — no web views — and you sign in with your own Alpaca API keys.

### Features
- Portfolio and positions, with detail for each holding
- Account summary: buying power, cash, market value, and activity history
- Buy and sell orders — market or limit, by share count or dollar amount
- Order history with filters and live status
- Market browser and symbol search
- Asset pages with charts, quotes, level-one book, news, and options
- Order updates on the Lock Screen and Dynamic Island via Live Activities
- Light and dark themes, plus Liquid Glass on iOS 26
- API keys stored in the Keychain, with optional Face ID

### Requirements
- iOS 18 or later (Liquid Glass needs iOS 26)
- An Alpaca account and your own API keys

### Disclaimer
Vicu is an independent third-party client. It isn't affiliated with or endorsed by Alpaca, and it needs your own Alpaca account and API keys. Trading carries risk.

---

## 简体中文

Vicu 是一个用 SwiftUI 写的 Alpaca 券商账户原生 iOS 客户端,没有网页套壳。用你自己的 Alpaca API 密钥登录即可。

### 功能
- 投资组合与持仓,每只持仓都有详情页
- 账户概览:购买力、现金、市值、活动记录
- 买入/卖出:市价或限价,按股数或按金额
- 订单记录,支持筛选与实时状态
- 行情浏览与代码搜索
- 资产页:图表、报价、一档盘口、新闻、期权
- 锁屏与灵动岛上的订单实时活动(Live Activities)
- 浅色/深色主题,iOS 26 上支持 Liquid Glass
- API 密钥存于钥匙串,可选 Face ID

### 运行要求
- iOS 18 及以上(Liquid Glass 需 iOS 26)
- 一个 Alpaca 账户及你自己的 API 密钥

### 免责声明
Vicu 是独立第三方客户端,与 Alpaca 无隶属或背书关系,需自备 Alpaca 账户与 API 密钥。交易有风险。
