package dev.roozbahani.trailmetrics.data.di

import android.content.Context
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationServices
import dev.roozbahani.trailmetrics.data.location.LocationRepositoryImpl
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import org.koin.dsl.module

val locationModule = module {
    single<FusedLocationProviderClient> {
        LocationServices.getFusedLocationProviderClient(get<Context>())
    }
    single<LocationRepository> {
        LocationRepositoryImpl(get())
    }
}
