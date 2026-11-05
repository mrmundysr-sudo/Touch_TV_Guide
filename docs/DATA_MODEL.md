# Shared data contract (Android and iOS must match)

Reference implementation: `core/src/main/kotlin/com/touch/tvguide/core/` (Kotlin). iOS ports these types and rules and the same test cases.

- **Channel** (feed): id, name, feedNumber?, logoUrl?, feedCategory?
- **Program** (feed): channelId, title, description?, start, stop (epoch ms). Key = `channelId|start`.
- **Customization** (user, stored separately from feed so refresh never overwrites it): numbers[channelId], categories[channelId], favoriteChannels, favoritePrograms.
- **HomeProfile**: zip, providerId, Customization. Only one exists; overwrite needs confirmation.

## Rules
- Effective number = user number, else feed number, else `?`. Sort ascending numerically (4.1 < 5); `?` last; tie -> name.
- Assign number: any other channel showing that number becomes `?`. `?` channels can be reassigned later.
- Category: user assignment overrides feed tag; channels with no category appear only in the full guide.
- Favorites list keeps numerical order. Reset (Home long-press) clears numbers and categories, keeps favorites.
- A channel with no programs in a window renders "No listings". Right-arrow limit = latest program stop.
- XMLTV: numeric `display-name` (or `lcn`) is the channel number; bad programmes are skipped; times without offset are UTC.
- Search: channels by name or effective number; programs by title/description; ordered by channel number.
