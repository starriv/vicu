enum AppIcon {
    enum Tab {
        static let home = "AlpacaTabIcon"
        static let markets = "chart.line.uptrend.xyaxis"
        static let search = "magnifyingglass"
        static let orders = "list.bullet.rectangle"
        static let more = "ellipsis.circle"
    }

    enum Portfolio {
        static let connected = "checkmark.seal.fill"
        static let warning = "exclamationmark.triangle.fill"
        static let history = "chart.xyaxis.line"
        static let missingCredentials = "key.slash"
    }

    enum Account {
        static let profile = "person.crop.circle.fill"
        static let buyingPower = "creditcard"
        static let cash = "dollarsign.circle"
        static let longMarketValue = "arrow.up.right.circle"
        static let shortMarketValue = "arrow.down.right.circle"
        static let activity = "clock.arrow.circlepath"
        static let activityFill = "checkmark.circle.fill"
        static let activityTransfer = "arrow.left.arrow.right.circle"
        static let activityDividend = "dollarsign.circle.fill"
        static let activityFee = "minus.circle.fill"
        static let activityOption = "slider.horizontal.3"
        static let activityCorporateAction = "building.columns.circle"
        static let activityFailure = "exclamationmark.triangle.fill"
        static let activityMore = "ellipsis.circle"
    }

    enum Position {
        static let empty = "tray"
        static let stock = "building.columns"
        static let etf = "square.grid.2x2"
        static let option = "arrow.trianglehead.branch"
        static let crypto = "bitcoinsign.circle"
    }

    enum More {
        static let orders = "list.bullet.rectangle"
        static let alpaca = "key.fill"
        static let notifications = "bell.badge.fill"
        static let settings = "gearshape.fill"
    }

    enum Alpaca {
        static let credential = "key.fill"
        static let credentialMissing = "key.slash"
        static let testConnection = "checkmark.shield"
        static let removeCredentials = "trash"
        static let connected = "checkmark.seal.fill"
        static let failed = "xmark.octagon.fill"
        static let testing = "hourglass"
        static let missing = "exclamationmark.triangle.fill"
    }

    enum Settings {
        static let appearance = "circle.lefthalf.filled"
        static let language = "globe"
        static let logoDev = "photo.on.rectangle.angled"
        static let notifications = "bell.badge.fill"
        static let tradeNotifications = "paperplane.fill"
        static let orderStatusNotifications = "checklist"
        static let accountActivityNotifications = "clock.arrow.circlepath"
    }

    enum Market {
        static let equity = "building.columns"
        static let crypto = "bitcoinsign.circle"
        static let regular = "sun.max.fill"
        static let preMarket = "sunrise.fill"
        static let afterHours = "sunset.fill"
        static let overnight = "moon.fill"
        static let closed = "pause.fill"
        static let favorites = "star.fill"
        static let popular = "flame.fill"
        static let search = "magnifyingglass"
        static let more = "ellipsis"
    }
}
