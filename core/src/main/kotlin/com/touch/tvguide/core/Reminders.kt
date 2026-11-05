package com.touch.tvguide.core

/** A reminder for one program. Key matches [Program.key]. */
data class Reminder(
    val programKey: String,
    val channelId: String,
    val channelName: String,
    val title: String,
    val startMillis: Long,
    val stopMillis: Long,
)

object ReminderLogic {
    const val DEFAULT_LEAD_MINUTES = 5

    fun fireAt(r: Reminder, leadMinutes: Int): Long = r.startMillis - leadMinutes * 60_000L

    /** A reminder can be set while the program has not started yet. */
    fun canRemind(p: Program, now: Long) = p.startMillis > now

    fun fromProgram(p: Program, channelName: String) =
        Reminder(p.key(), p.channelId, channelName, p.title, p.startMillis, p.stopMillis)

    data class Reconciled(val keep: List<Reminder>, val updated: List<Reminder>, val dropped: List<Reminder>)

    /**
     * After a feed refresh: reminders whose program is gone from the feed are dropped; those whose program
     * moved (same channel, same title, overlapping) are updated; ended ones are dropped. Pending set = keep + updated.
     */
    fun reconcile(reminders: List<Reminder>, programs: List<Program>, now: Long): Reconciled {
        val byKey = programs.associateBy { it.key() }
        val keep = ArrayList<Reminder>(); val upd = ArrayList<Reminder>(); val drop = ArrayList<Reminder>()
        for (r in reminders) {
            if (r.startMillis <= now) { drop += r; continue }
            val exact = byKey[r.programKey]
            if (exact != null && exact.title == r.title) {
                if (exact.stopMillis != r.stopMillis) upd += r.copy(stopMillis = exact.stopMillis) else keep += r
                continue
            }
            val moved = programs.firstOrNull { it.channelId == r.channelId && it.title == r.title && it.startMillis > now &&
                kotlin.math.abs(it.startMillis - r.startMillis) <= 6 * 3_600_000L }
            if (moved != null) upd += r.copy(programKey = moved.key(), startMillis = moved.startMillis, stopMillis = moved.stopMillis)
            else drop += r
        }
        return Reconciled(keep, upd, drop)
    }
}

/** Feed refresh rule: the feed is fetched at most once every 24 hours, however the refresh is triggered. */
object FeedPolicy {
    const val MIN_INTERVAL_MILLIS = 24L * 3_600_000L

    /** [force] is only for "nothing cached yet" or "the user changed the feed URL". */
    fun shouldRefresh(lastFetchMillis: Long, now: Long, force: Boolean = false): Boolean =
        force || lastFetchMillis <= 0 || now < lastFetchMillis || now - lastFetchMillis >= MIN_INTERVAL_MILLIS

    fun nextAllowed(lastFetchMillis: Long): Long = if (lastFetchMillis <= 0) 0 else lastFetchMillis + MIN_INTERVAL_MILLIS
}
