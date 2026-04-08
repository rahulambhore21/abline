# Quick Fix Guide - 2 Steps

## Step 1: Backup Current File (Optional)
```
Location: app\lib\voice_call_screen.dart
Action: You can keep a copy as backup
```

## Step 2: Use the Corrected File

### Windows (File Explorer):
1. Open: `app\lib\`
2. Find: `voice_call_screen_new.dart` ✅ (corrected)
3. Find: `voice_call_screen.dart` ❌ (old)
4. Delete: `voice_call_screen.dart`
5. Rename: `voice_call_screen_new.dart` → `voice_call_screen.dart`

### Command Line:
```bash
cd app\lib
del voice_call_screen.dart
ren voice_call_screen_new.dart voice_call_screen.dart
```

## Step 3: Clean Build
```bash
cd app
flutter clean
flutter pub get
flutter run
```

✅ **Build should now succeed!**

---

## What Changed?

| Issue | Old Code | New Code |
|-------|----------|----------|
| Callback params | `(connection, speakers, totalVolume)` | `(connection, speakers, totalVolume, publishVolume)` |
| UID access | `speaker.uid` (crashes if null) | `speaker.uid ?? 0` (safe) |
| Volume access | `speaker.volume` (crashes if null) | `speaker.volume ?? 0` (safe) |
| VAD access | `speaker.vad` (crashes if null) | `speaker.vad ?? 0` (safe) |

---

## Key Points

✅ Added missing 4th parameter: `publishVolume`
✅ Null-safe property access using `??` operator
✅ All braces properly matched
✅ Full file verified for syntax errors

---

## Verification

After applying the fix:

```bash
flutter run
```

You should see:
```
✅ Build succeeded
✅ App starts
✅ Can join voice call
✅ Speaker detection works
```

If you still see errors:
1. Verify you used `voice_call_screen_new.dart` content
2. Run `flutter clean` again
3. Check you renamed the file correctly

---

## File Locations

- ✅ **Corrected file**: `app/lib/voice_call_screen_new.dart`
- ❌ **Old file**: `app/lib/voice_call_screen.dart` (to be replaced)

---

## Done! 🎉

Your Flutter app should now build successfully!

Next: Test with 2+ users in a voice call.
