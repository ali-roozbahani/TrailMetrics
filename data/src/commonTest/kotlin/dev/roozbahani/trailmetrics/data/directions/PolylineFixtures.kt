package dev.roozbahani.trailmetrics.data.directions

object PolylineFixtures {
    // Google's reference example from the Encoded Polyline Algorithm Format documentation.
    const val REFERENCE = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"

    val REFERENCE_POINTS = listOf(
        38.5 to -120.2,
        40.7 to -120.95,
        43.252 to -126.453,
    )

    // Ends on 'q', which has the continuation bit set: the decoder needs one more character.
    val TRUNCATED = REFERENCE.dropLast(2)

    // The final '@' replaced by '_' (0x20 after the -63 offset): only the continuation bit set.
    val UNTERMINATED = REFERENCE.dropLast(1) + "_"
}
