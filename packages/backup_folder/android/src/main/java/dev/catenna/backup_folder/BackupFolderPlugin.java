package dev.catenna.backup_folder;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.content.UriPermission;
import android.database.Cursor;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.provider.DocumentsContract;

import androidx.annotation.NonNull;

import java.io.OutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * Папка для резервных копий через Storage Access Framework: выбор папки с постоянным доступом,
 * запись, перечисление и удаление файлов только в ней. Файловые операции — не в главном потоке.
 */
public class BackupFolderPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
        PluginRegistry.ActivityResultListener {
    private static final int PICK_FOLDER = 0x4C05;
    private static final int SAVE_AS = 0x4C07;

    private MethodChannel channel;
    private Context context;
    private ActivityPluginBinding activityBinding;
    private MethodChannel.Result pendingPick;
    private MethodChannel.Result pendingSave;
    private byte[] pendingSaveBytes;
    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "catenna/backup_folder");
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
        binding.addActivityResultListener(this);
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
        if (activityBinding != null) activityBinding.removeActivityResultListener(this);
        activityBinding = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "pickFolder":
                pickFolder(result);
                return;
            case "saveAs":
                saveAs(result, (String) call.argument("name"), (byte[]) call.argument("bytes"), (String) call.argument("mime"));
                return;
            case "hasAccess":
                result.success(hasAccess(Uri.parse((String) call.argument("folder"))));
                return;
            case "folderName":
                background(result, () -> folderName(Uri.parse((String) call.argument("folder"))));
                return;
            case "writeFile":
                background(result, () -> writeFile(Uri.parse((String) call.argument("folder")),
                        (String) call.argument("name"), (byte[]) call.argument("bytes"), (String) call.argument("mime")));
                return;
            case "listFiles":
                background(result, () -> listFiles(Uri.parse((String) call.argument("folder"))));
                return;
            case "deleteFile":
                background(result, () -> {
                    Uri tree = Uri.parse((String) call.argument("folder"));
                    Uri doc = DocumentsContract.buildDocumentUriUsingTree(tree, (String) call.argument("id"));
                    DocumentsContract.deleteDocument(context.getContentResolver(), doc);
                    return null;
                });
                return;
            default:
                result.notImplemented();
        }
    }

    private interface Work {
        Object run() throws Exception;
    }

    private void background(MethodChannel.Result result, Work work) {
        io.execute(() -> {
            try {
                Object value = work.run();
                main.post(() -> result.success(value));
            } catch (Exception e) {
                main.post(() -> result.error("io", e.toString(), null));
            }
        });
    }

    private void pickFolder(MethodChannel.Result result) {
        Activity activity = activityBinding == null ? null : activityBinding.getActivity();
        if (activity == null) {
            result.error("no_activity", "Нет активного экрана для выбора папки", null);
            return;
        }
        if (pendingPick != null) {
            result.error("busy", "Выбор папки уже открыт", null);
            return;
        }
        pendingPick = result;
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        activity.startActivityForResult(intent, PICK_FOLDER);
    }

    /** «Сохранить как»: системный диалог создания файла — человек сам выбирает место и имя. */
    private void saveAs(MethodChannel.Result result, String name, byte[] bytes, String mime) {
        Activity activity = activityBinding == null ? null : activityBinding.getActivity();
        if (activity == null) {
            result.error("no_activity", "Нет активного экрана для сохранения файла", null);
            return;
        }
        if (pendingSave != null) {
            result.error("busy", "Сохранение файла уже открыто", null);
            return;
        }
        pendingSave = result;
        pendingSaveBytes = bytes;
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType(mime == null ? "application/octet-stream" : mime);
        intent.putExtra(Intent.EXTRA_TITLE, name);
        activity.startActivityForResult(intent, SAVE_AS);
    }

    private boolean onSaveAsResult(int resultCode, Intent data) {
        MethodChannel.Result result = pendingSave;
        byte[] bytes = pendingSaveBytes;
        pendingSave = null;
        pendingSaveBytes = null;
        if (result == null) return true;
        if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null || bytes == null) {
            result.success(false); // отменено
            return true;
        }
        Uri doc = data.getData();
        background(result, () -> {
            ContentResolver r = context.getContentResolver();
            try (OutputStream out = r.openOutputStream(doc, "w")) {
                if (out == null) throw new IllegalStateException("Файл недоступен для записи");
                out.write(bytes);
                out.flush();
            } catch (Exception e) {
                // недописанный файл не оставляем
                try {
                    DocumentsContract.deleteDocument(r, doc);
                } catch (Exception ignored) {
                }
                throw e;
            }
            return true;
        });
        return true;
    }

    @Override
    public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == SAVE_AS) return onSaveAsResult(resultCode, data);
        if (requestCode != PICK_FOLDER) return false;
        MethodChannel.Result result = pendingPick;
        pendingPick = null;
        if (result == null) return true;
        if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null) {
            result.success(null);
            return true;
        }
        Uri tree = data.getData();
        try {
            context.getContentResolver().takePersistableUriPermission(tree,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            result.success(tree.toString());
        } catch (Exception e) {
            result.error("permission", e.toString(), null);
        }
        return true;
    }

    private boolean hasAccess(Uri tree) {
        for (UriPermission p : context.getContentResolver().getPersistedUriPermissions()) {
            if (p.getUri().equals(tree) && p.isWritePermission() && p.isReadPermission()) return true;
        }
        return false;
    }

    private Uri folderDoc(Uri tree) {
        return DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree));
    }

    private String folderName(Uri tree) {
        String[] cols = {DocumentsContract.Document.COLUMN_DISPLAY_NAME};
        try (Cursor c = context.getContentResolver().query(folderDoc(tree), cols, null, null, null)) {
            if (c != null && c.moveToFirst()) return c.getString(0);
        }
        return null;
    }

    private String writeFile(Uri tree, String name, byte[] bytes, String mime) throws Exception {
        ContentResolver r = context.getContentResolver();
        Uri doc = DocumentsContract.createDocument(r, folderDoc(tree), mime == null ? "application/octet-stream" : mime, name);
        if (doc == null) throw new IllegalStateException("Папка не дала создать файл");
        try (OutputStream out = r.openOutputStream(doc, "w")) {
            if (out == null) throw new IllegalStateException("Файл недоступен для записи");
            out.write(bytes);
            out.flush();
        } catch (Exception e) {
            // недописанный файл не оставляем — его нельзя было бы восстановить
            try {
                DocumentsContract.deleteDocument(r, doc);
            } catch (Exception ignored) {
            }
            throw e;
        }
        return DocumentsContract.getDocumentId(doc);
    }

    private List<Map<String, Object>> listFiles(Uri tree) {
        Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree));
        String[] cols = {
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
        };
        List<Map<String, Object>> out = new ArrayList<>();
        try (Cursor c = context.getContentResolver().query(children, cols, null, null, null)) {
            while (c != null && c.moveToNext()) {
                if (DocumentsContract.Document.MIME_TYPE_DIR.equals(c.getString(4))) continue;
                Map<String, Object> m = new HashMap<>();
                m.put("id", c.getString(0));
                m.put("name", c.getString(1));
                m.put("modified", c.isNull(2) ? 0L : c.getLong(2));
                m.put("size", c.isNull(3) ? 0L : c.getLong(3));
                out.add(m);
            }
        }
        return out;
    }
}
