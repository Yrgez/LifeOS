package dev.lifeos.local_reminders;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

/**
 * Расписание напоминаний: хранится в SharedPreferences плагина, чтобы его можно было восстановить после
 * перезагрузки, и ставится будильниками AlarmManager (setAndAllowWhileIdle — без разрешения на точные будильники).
 */
final class ReminderStore {
    private static final String PREFS = "lifeos_local_reminders";
    private static final String KEY = "items";

    static final class Item {
        final int id;
        final long at;
        final String title;
        final String body;

        Item(int id, long at, String title, String body) {
            this.id = id;
            this.at = at;
            this.title = title;
            this.body = body;
        }
    }

    private ReminderStore() {
    }

    static List<Item> load(Context context) {
        List<Item> out = new ArrayList<>();
        String raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, "[]");
        try {
            JSONArray a = new JSONArray(raw);
            for (int i = 0; i < a.length(); i++) {
                JSONObject o = a.getJSONObject(i);
                out.add(new Item(o.getInt("id"), o.getLong("at"), o.getString("title"), o.getString("body")));
            }
        } catch (Exception ignored) {
            // повреждённое расписание просто не восстанавливается — приложение поставит новое при открытии
        }
        return out;
    }

    private static void save(Context context, List<Item> items) {
        JSONArray a = new JSONArray();
        try {
            for (Item it : items) {
                JSONObject o = new JSONObject();
                o.put("id", it.id);
                o.put("at", it.at);
                o.put("title", it.title);
                o.put("body", it.body);
                a.put(o);
            }
        } catch (Exception ignored) {
        }
        SharedPreferences.Editor e = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit();
        e.putString(KEY, a.toString());
        e.apply();
    }

    private static PendingIntent intentFor(Context context, Item it) {
        Intent i = new Intent(context, ReminderReceiver.class);
        i.putExtra(ReminderReceiver.EXTRA_ID, it.id);
        i.putExtra(ReminderReceiver.EXTRA_TITLE, it.title);
        i.putExtra(ReminderReceiver.EXTRA_BODY, it.body);
        return PendingIntent.getBroadcast(context, it.id, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private static void arm(Context context, AlarmManager am, Item it) {
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, it.at, intentFor(context, it));
    }

    /** Отменяет прежнее расписание и ставит новое (только будущие напоминания). */
    static void replaceAll(Context context, List<Item> items) {
        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        for (Item old : load(context)) {
            am.cancel(intentFor(context, old));
        }
        long now = System.currentTimeMillis();
        List<Item> future = new ArrayList<>();
        for (Item it : items) {
            if (it.at > now) {
                future.add(it);
                arm(context, am, it);
            }
        }
        save(context, future);
    }

    /** После перезагрузки будильники пропадают — ставим их заново из сохранённого расписания. */
    static void restore(Context context) {
        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        long now = System.currentTimeMillis();
        List<Item> future = new ArrayList<>();
        for (Item it : load(context)) {
            if (it.at > now) {
                future.add(it);
                arm(context, am, it);
            }
        }
        save(context, future);
    }
}
