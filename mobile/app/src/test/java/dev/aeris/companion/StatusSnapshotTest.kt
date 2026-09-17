package dev.aeris.companion

import org.junit.Assert.*
import org.junit.Test

class StatusSnapshotTest {
    @Test fun responseAheadOfUiTickIsImmediatelyFresh() {
        val state = StatusSnapshot("live", receivedAt = 2_350)
        assertTrue(state.isFresh(now = 2_000))
        assertTrue(state.serviceIsFresh(serverTime = 100, updatedAt = 100, now = 2_000))
        assertTrue(state.isFresh(now = 3_000))
    }

    @Test fun repeatedPollsNeverProduceAnOfflineFrame() {
        // Simulate frames immediately before/after two-second poll responses,
        // with their receipt times always ahead of the one-second UI ticker.
        var state = StatusSnapshot("live", receivedAt = 100)
        for (tick in 1_000L..30_000L step 1_000) {
            assertTrue(state.isFresh(tick))
            if (tick % 2_000 == 0L) state = StatusSnapshot("live", tick + 350)
            assertTrue(state.isFresh(tick))
            assertTrue(state.serviceIsFresh(100, 99, tick))
        }
    }

    @Test fun retainedReadingExpiresWithoutAnotherSuccessfulResponse() {
        val state = StatusSnapshot("last good reading", receivedAt = 2_350)
        assertTrue(state.isFresh(8_000))
        assertTrue(state.isFresh(12_350))
        assertFalse(state.isFresh(12_351))
        assertFalse(state.serviceIsFresh(100, 100, 12_351))
        assertTrue(StatusSnapshot("recovered", 20_350).isFresh(20_000))
    }

    @Test fun freshHttpResponseCannotReviveStaleServiceData() {
        val state = StatusSnapshot("live", receivedAt = 2_350)
        assertTrue(state.isFresh(4_000))
        assertTrue(state.serviceIsFresh(100, 91, 3_350))
        assertFalse(state.serviceIsFresh(100, 91, 3_351))
        assertFalse(state.serviceIsFresh(100, 89, 2_000))
        assertFalse(state.serviceIsFresh(100, 101, 2_000))
        assertFalse(state.serviceIsFresh(100, 0, 2_000))
    }
}
