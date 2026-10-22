package dev.roozbahani.trailmetrics.domain.repository

/**
 * A user profile is stored but cannot be decoded (corrupt, empty or from another shape).
 * [UserProfileRepository.getUserProfile] throws it, so callers can tell it from "nothing saved"
 * (`null`). The stored value is left untouched; saving a new profile overwrites it.
 */
class StoredUserProfileUnreadableException(cause: Throwable?) :
    Exception("The stored user profile cannot be decoded", cause)
