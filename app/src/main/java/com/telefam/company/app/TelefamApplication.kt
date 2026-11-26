package com.telefam.company.app

import android.app.Application
import com.telefam.company.app.core.TelefamNativeBridge
import com.telefam.company.app.data.FeedRepository
import com.telefam.company.app.data.TelefamRepository
import com.telefam.company.app.data.local.TelefamDatabase
import com.telefam.company.app.feed.FeedPlayerController
import com.telefam.company.app.feed.Media3FeedPlaybackController
import com.telefam.company.app.network.AndroidNetworkMonitor
import com.telefam.company.app.network.TelefamNetworkClient
import com.telefam.company.app.security.TelefamCryptoVault

class TelefamApplication : Application() {
    lateinit var repository: TelefamRepository
        private set
    lateinit var feedRepository: FeedRepository
        private set
    lateinit var networkMonitor: AndroidNetworkMonitor
        private set
    lateinit var feedPlayerController: FeedPlayerController
        private set

    override fun onCreate() {
        super.onCreate()
        val vault = TelefamCryptoVault(this)
        val masterKey = vault.deriveNativeMasterKey32()
        val vaultFile = filesDir.resolve("telefam_vault.dat").absolutePath
        val bridge = TelefamNativeBridge(vaultFile, masterKey)
        val deviceIdentity = vault.buildDeviceIdentity(bridge)
        val db = TelefamDatabase.create(this)
        val api = TelefamNetworkClient.createService()

        repository = TelefamRepository(
            context = this,
            dao = db.dao(),
            api = api,
            vault = vault,
            bridge = bridge,
            deviceIdentity = deviceIdentity
        )
        feedRepository = FeedRepository(
            coreRepo = repository,
            dao = db.dao(),
            api = api,
            vault = vault
        )
        networkMonitor = AndroidNetworkMonitor(this)
        feedPlayerController = Media3FeedPlaybackController(this)
    }
}
