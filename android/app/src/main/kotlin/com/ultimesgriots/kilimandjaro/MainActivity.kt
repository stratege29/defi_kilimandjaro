package com.ultimesgriots.kilimandjaro

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    /**
     * Déclare les canaux de notification utilisés par les pushes FCM.
     *
     * Sur Android 8+ (O), une notification dont le channelId n'existe pas est
     * reléguée à un canal fallback générique. On crée ici les canaux référencés
     * côté Cloud Functions (cf functions/src/utils/fcm.ts) pour un libellé et
     * une priorité corrects. Suffisant pour notre flux : l'appareil s'abonne au
     * topic au boot (app ouverte → onCreate exécuté) avant de recevoir un push.
     * Idempotent : recréer un canal existant est un no-op côté système.
     */
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return

        val contentUpdates = NotificationChannel(
            "content_updates",
            "Nouveaux packs",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Nouveaux packs et mises à jour de contenu"
        }
        manager.createNotificationChannel(contentUpdates)

        val duelChallenges = NotificationChannel(
            "duel_challenges",
            "Défis",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Invitations à des duels en temps réel"
        }
        manager.createNotificationChannel(duelChallenges)
    }
}
