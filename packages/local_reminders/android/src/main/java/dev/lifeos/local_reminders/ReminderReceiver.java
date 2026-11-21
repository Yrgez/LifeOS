package dev.lifeos.local_reminders;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

/** Срабатывание будильника: показывает уведомление. Нажатие открывает приложение. */
public class ReminderReceiver extends BroadcastReceiver {
    static final String EXTRA_ID = "id";
    static final String EXTRA_TITLE = "title";
    static final String EXTRA_BODY = "body";
    static final String CHANNEL = "lifeos_reminders";

    static void ensureChannel(Context context) {
        NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm.getNotificationChannel(CHANNEL) == null) {
            NotificationChannel ch = new NotificationChannel(CHANNEL, "Напоминания", NotificationManager.IMPORTANCE_DEFAULT);
            ch.setDescription("Отметка дня, сроки счетов, обзор недели");
            nm.createNotificationChannel(ch);
        }
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= 24 && !nm.areNotificationsEnabled()) return;
        ensureChannel(context);
        int id = intent.getIntExtra(EXTRA_ID, 0);
        String title = intent.getStringExtra(EXTRA_TITLE);
        String body = intent.getStringExtra(EXTRA_BODY);

        Intent launch = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        PendingIntent open = launch == null ? null
                : PendingIntent.getActivity(context, id, launch, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        // на экране блокировки — только нейтральная строка: суммы и заметки видны после разблокировки
        Notification publicVersion = new Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_lifeos_reminder)
                .setContentTitle("Catenna")
                .setContentText("Напоминание")
                .build();
        Notification.Builder b = new Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_lifeos_reminder)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(new Notification.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setPublicVersion(publicVersion);
        if (open != null) b.setContentIntent(open);
        try {
            nm.notify(id, b.build());
        } catch (SecurityException ignored) {
            // разрешение на уведомления отозвано — молча пропускаем
        }
    }
}
