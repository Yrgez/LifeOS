package dev.lifeos.local_reminders;

import android.Manifest;
import android.app.Activity;
import android.app.NotificationManager;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/** Локальные напоминания: разрешение на уведомления и замена расписания целиком. */
public class LocalRemindersPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
        PluginRegistry.RequestPermissionsResultListener {
    private static final int REQUEST_NOTIFICATIONS = 0x4C06;

    private MethodChannel channel;
    private Context context;
    private ActivityPluginBinding activityBinding;
    private MethodChannel.Result pendingPermission;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "lifeos/local_reminders");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activityBinding = binding;
        binding.addRequestPermissionsResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        if (activityBinding != null) activityBinding.removeRequestPermissionsResultListener(this);
        activityBinding = null;
    }

    private boolean permitted() {
        if (Build.VERSION.SDK_INT >= 33
                && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            return false;
        }
        NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        return nm.areNotificationsEnabled();
    }

    @Override
    @SuppressWarnings("unchecked")
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "permitted":
                result.success(permitted());
                return;
            case "requestPermission":
                requestPermission(result);
                return;
            case "replaceAll":
                try {
                    List<Map<String, Object>> raw = call.argument("items");
                    List<ReminderStore.Item> items = new ArrayList<>();
                    if (raw != null) {
                        for (Map<String, Object> m : raw) {
                            items.add(new ReminderStore.Item(((Number) m.get("id")).intValue(), ((Number) m.get("at")).longValue(),
                                    (String) m.get("title"), (String) m.get("body")));
                        }
                    }
                    ReminderReceiver.ensureChannel(context);
                    ReminderStore.replaceAll(context, items);
                    result.success(null);
                } catch (Exception e) {
                    result.error("schedule", e.toString(), null);
                }
                return;
            default:
                result.notImplemented();
        }
    }

    private void requestPermission(MethodChannel.Result result) {
        if (permitted()) {
            result.success(true);
            return;
        }
        Activity activity = activityBinding == null ? null : activityBinding.getActivity();
        if (Build.VERSION.SDK_INT < 33 || activity == null) {
            // до Android 13 разрешения нет — уведомления включаются в системных настройках приложения
            result.success(permitted());
            return;
        }
        if (pendingPermission != null) {
            result.error("busy", "Запрос разрешения уже открыт", null);
            return;
        }
        pendingPermission = result;
        activity.requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, REQUEST_NOTIFICATIONS);
    }

    @Override
    public boolean onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        if (requestCode != REQUEST_NOTIFICATIONS) return false;
        MethodChannel.Result r = pendingPermission;
        pendingPermission = null;
        if (r != null) r.success(permitted());
        return true;
    }
}
