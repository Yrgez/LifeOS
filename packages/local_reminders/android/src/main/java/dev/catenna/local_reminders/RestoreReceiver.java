package dev.catenna.local_reminders;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Перезагрузка телефона или обновление приложения: будильники пропали — восстанавливаем расписание. */
public class RestoreReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String a = intent.getAction();
        if (Intent.ACTION_BOOT_COMPLETED.equals(a) || Intent.ACTION_MY_PACKAGE_REPLACED.equals(a)) {
            ReminderStore.restore(context);
        }
    }
}
