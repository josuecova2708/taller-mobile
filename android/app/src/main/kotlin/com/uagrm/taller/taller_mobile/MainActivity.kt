package com.uagrm.taller.taller_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        crearCanalDeAlertas()
    }

    /**
     * Canal de las notificaciones push (CU18). Es de importancia alta para
     * que el aviso de una orden nueva suene y aparezca sobre la pantalla.
     * El id debe coincidir con el que usa el backend (`CANAL_ALERTAS`) y con
     * el canal por defecto declarado en AndroidManifest.xml.
     */
    private fun crearCanalDeAlertas() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val canal = NotificationChannel(
            "alertas",
            "Alertas de mantenimiento",
            NotificationManager.IMPORTANCE_HIGH,
        )
        canal.description = "Avisos de órdenes de trabajo nuevas"
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(canal)
    }
}
