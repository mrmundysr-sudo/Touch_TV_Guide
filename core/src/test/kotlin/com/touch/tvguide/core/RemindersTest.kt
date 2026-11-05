package com.touch.tvguide.core

import kotlin.test.*

class RemindersTest {
    private val now = 1_000_000L
    private fun prog(ch: String, start: Long, title: String = "Show", dur: Long = 3_600_000) = Program(ch, title, null, start, start + dur)

    @Test fun fireTimeAndEligibility() {
        val p = prog("a", now + 600_000)
        val r = ReminderLogic.fromProgram(p, "ABC")
        assertEquals(p.startMillis - 300_000, ReminderLogic.fireAt(r, 5))
        assertTrue(ReminderLogic.canRemind(p, now)); assertFalse(ReminderLogic.canRemind(prog("a", now - 1), now))
    }

    @Test fun reconcileKeepsDropsAndUpdates() {
        val same = prog("a", now + 1_000_000)
        val gone = prog("a", now + 5_000_000, "Gone")
        val moved = prog("b", now + 7_000_000, "Moved")
        val past = prog("a", now - 10, "Past")
        val rs = listOf(same, gone, moved, past).map { ReminderLogic.fromProgram(it, "X") }
        val feed = listOf(same, prog("b", now + 7_900_000, "Moved"), prog("a", now + 9_000_000, "Other"))
        val out = ReminderLogic.reconcile(rs, feed, now)
        assertEquals(listOf(same.key()), out.keep.map { it.programKey })
        assertEquals(listOf("b|${now + 7_900_000}"), out.updated.map { it.programKey })
        assertEquals(setOf("Gone", "Past"), out.dropped.map { it.title }.toSet())
    }

    @Test fun refreshPolicyIsDailyAtMost() {
        val h = 3_600_000L
        assertTrue(FeedPolicy.shouldRefresh(0, now))
        assertFalse(FeedPolicy.shouldRefresh(now, now + 23 * h))
        assertTrue(FeedPolicy.shouldRefresh(now, now + 24 * h))
        assertTrue(FeedPolicy.shouldRefresh(now, now + 1, force = true))
        assertTrue(FeedPolicy.shouldRefresh(now + 5, now)) // clock went backwards
        assertEquals(now + 24 * h, FeedPolicy.nextAllowed(now))
    }
}
