package dev.aeris.companion

/** Receipt time is monotonic; payload and receipt are published together. */
internal data class StatusSnapshot<T>(val payload: T, val receivedAt: Long) {
    // A response can arrive after the UI's most recent clock tick. It is then
    // brand new, not stale; the next tick will catch up with the receipt time.
    fun ageMillis(now: Long): Long = (now - receivedAt).coerceAtLeast(0)

    fun isFresh(now: Long): Boolean = ageMillis(now) <= 10_000

    fun serviceIsFresh(serverTime: Long, updatedAt: Long, now: Long): Boolean {
        if (!isFresh(now) || serverTime <= 0 || updatedAt <= 0) return false
        val serverAge = serverTime - updatedAt
        return serverAge in 0..10 && serverAge * 1000 + ageMillis(now) <= 10_000
    }
}
