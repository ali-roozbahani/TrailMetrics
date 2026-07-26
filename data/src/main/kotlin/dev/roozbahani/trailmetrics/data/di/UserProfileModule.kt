package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.data.user.UserProfileRepositoryImpl
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import org.koin.dsl.module

val userProfileModule = module {
    single<UserProfileRepository> {
        UserProfileRepositoryImpl(sharedPreferences = get())
    }
}
