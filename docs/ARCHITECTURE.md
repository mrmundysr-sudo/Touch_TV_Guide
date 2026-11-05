# iOS architecture

```
Packages/TVGuideCore   (SwiftPM, Foundation only — builds and tests with `swift test`)
  Models            Channel, Program, GuideData, Customization, HomeProfile
  GuideLogic        sorting, numbers, duplicates, categories, favorites, search, windows   (port of Android GuideLogic)
  XmltvParser/Gzip  XMLTV → GuideData (fails closed on bad/truncated files); gzip via Compression
  Markets           zip → nearest markets, channel → market, providers
  Reminders         reminder rules, reconcile after refresh, 64-notification cap, FeedPolicy (≤ 1 download / 24 h)
  GuideRepository   actor: cache, refresh, customization, reminders; talks to FeedDownloading / ReminderScheduling protocols
  SampleFeed        labelled preview data
App/TouchTVGuide     (SwiftUI, iOS 17)
  Services          FeedConfiguration (+ URLSessionDownloader), AppSettings, NotificationService, LocationService
  AppModel          @MainActor ObservableObject; the only thing views talk to
  Views             Setup, GuideScreen + GuideGrid, details, channel editor/manager, search, reminders, settings, help
```

Dependency direction: Views → AppModel → TVGuideCore. TVGuideCore never imports UIKit/SwiftUI, so it also runs under `swift test` on any machine with Swift. The feed provider is replaceable in `FeedDownloading` + `XmltvParser` + `MarketLogic.filterFor` without touching Views.

## Guide grid
One horizontal `ScrollView` holds a fixed time header and a vertical `ScrollView` of lazily-created channel rows. The channel cell in each row (and the header's "Channel" corner) is offset by the horizontal scroll position, so it stays pinned. Content width = `(coverage minutes × 4 pt) + channel column`, so scrolling ends exactly where the data ends. Earlier / Now / Later jump with `ScrollViewReader` to 30-minute slot anchors.

## Persistence
Application Support/TouchTVGuide: `guide.json`, `custom.json`, `home.json`, `reminders.json`, `meta.json`, `feed-cache.xml.gz` — independent atomic files. Preferences (theme, text size, lead time, feed address) are in UserDefaults.

## Tests
* `swift test` (Packages/TVGuideCore): parser (real-feed fixture incl. DOCTYPE, time zones, malformed), gzip, rules, markets (incl. bundled data), reminders, repository (cache, daily limit, failure safety, customization survival, relaunch, market change, sample mode, reminders).
* `xcodebuild test` (TouchTVGuideTests): AppModel flows (setup → guide, reminder permission, duplicate numbers, sample labelling), settings gate, grid bounds.
