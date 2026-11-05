# Touch TV Guide (iOS) — privacy disclosures

_Draft for the App Store listing and a hosted privacy-policy page; owner to add contact details before publishing._

* **No account, no ads, no analytics, no tracking.** No third-party SDKs.
* **On device only:** zip code, chosen market and provider, channel numbers / categories / order / favorites, reminders, and a saved copy of the public guide.
* **Location (optional, "While Using the App"):** requested only after the user taps *Use my approximate location* and confirms an explanation. Reduced accuracy; read once to suggest a zip; not stored or transmitted. Declining leaves manual zip entry fully working. Info.plist key: `NSLocationWhenInUseUsageDescription`.
* **Notifications:** requested only when the user sets their first reminder, after an explanation. Used only for the reminders the user created. Denial is handled (explanation + link to iOS Settings).
* **Network:** the only request is downloading the public guide file (at most once per day) from the configured feed host, which can see the device IP address like any web server. Channel logo images, if the feed has them, load from the URLs in the feed.
* **App Store privacy "nutrition label":** Data Not Collected. (Location is processed on device and not collected.)
