# Fix: Trade progressive loading

> **日期**: 2026-06-18

## 问题描述

从资产详情页进入 Trade 页面时，页面长时间停留在整页 skeleton。用户无法立即看到输入区和数字键盘，体感上像交易页卡住。

## 根因分析

- `TradeSimpleView` 用 `context == nil` 控制整页 skeleton，导致 account、asset、position、market snapshot 任一请求未完成时都不能渲染主体 UI。
- `fetchTradeContext` 会等待 market snapshot，snapshot 本质是估价/行情补充，不应该阻塞交易输入界面。
- Trade context Rx 管线对请求做了 250ms debounce，页面进入时人为增加首屏等待。
- 从 AssetDetail 跳转 Trade 时没有复用详情页已经拥有的 asset、position、quote、trade 数据。

## 修复方案

- 新增 `TradeSeedContext`，从资产详情页把 account、asset、position、quote、trade、feed 传入 Trade。
- Trade Store 使用 seed 做乐观 UI：价格、持仓和可用信息优先使用真实 context，其次使用 seed。
- `AppModel` 将 Trade 数据拆成 `fetchTradeCoreContext` 和 `fetchTradeSnapshot`。
- Trade Rx load pipeline 改为 core context 成功立即 emit，market snapshot 后续 emit 并补充 quote/feed/session。
- 移除 Trade context 请求的 250ms debounce。
- Trade 简单下单页不再因为 `context == nil` 展示整页 skeleton；提交校验仍由 `isLoadingContext` 控制，避免未确认 context 时提交订单。

## 修改文件

| 文件 | 变更 |
| --- | --- |
| `Features/Trade/TradeStore.swift` | 新增 seed context、乐观字段读取、core/snapshot 分片事件、移除 context debounce。 |
| `Features/Trade/TradeView.swift` | 支持 seed 初始化；调整 skeleton 展示条件，保留加载期间提交禁用。 |
| `App/AppModel/AppModel+Markets.swift` | 拆分 Trade core context 和 snapshot 获取。 |
| `Features/AssetDetail/AssetDetailView.swift` | 从详情页打开 Trade 时传入已有资产、持仓和实时 quote/trade。 |

## 验证方式

- `build_sim` 通过，0 warnings，0 errors。
- `git diff --check` 通过。

*创建于: 2026-06-18*

## 变更记录

### 2026-06-18 修复: Trade confirmation notice and button polish

- 统一 warning notice 和 confirmation notice 的宽度与卡片样式，避免同组提示出现不同宽度。
- 保留 iOS 26 `.glassProminent` 提交按钮，并将按钮文字/进度指示改为白色，修复 Sell 文本在红色 prominent glass 上对比度不足的问题。
