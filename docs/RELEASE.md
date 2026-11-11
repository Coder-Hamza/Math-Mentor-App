# Release: building the MathMentor AI APK

These steps produce a signed `app-release.apk` that you can install on any Android 7.0+
(API 24) phone. **The signing key is never stored in this repository.** You create it once,
keep it safe, and point the build at it through `mobile/android/key.properties`, which is
gitignored.

## 0. Prerequisites

- Android Studio installed, so the Android SDK exists and `flutter doctor` shows
  **[√] Android toolchain**. See "Android SDK setup" in `README.md`.
- `keytool` comes with the JDK that Android Studio bundles:
  `C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe`.

## 1. Create your upload keystore (once)

Run this in PowerShell, from a folder **outside** the repository:

```powershell
mkdir $env:USERPROFILE\keys -Force
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v `
  -keystore $env:USERPROFILE\keys\mathmentor-upload.jks `
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

The command asks for a password and your name. Back up the `.jks` file and its password,
for example in a password manager. **If you lose the key, you cannot publish updates to
the same app.**

## 2. Point the build at the key

```powershell
cd mobile\android
copy key.properties.example key.properties
notepad key.properties
```

Fill in the passwords, `keyAlias=upload`, and the **absolute** keystore path with forward
slashes, for example `storeFile=C:/Users/you/keys/mathmentor-upload.jks`.

`key.properties`, `*.jks` and `*.keystore` are already in `mobile/android/.gitignore`.
Before committing, run `git status` and check that neither file is listed.

How the build uses it (`mobile/android/app/build.gradle.kts`):
- If `key.properties` exists, the release build is signed with your key.
- If it does not, the release build falls back to the **debug** key so that
  `flutter run --release` still works. Never distribute a debug-signed APK.

## 3. Choose the backend URL

The URL is compiled into the APK. Release builds only allow **HTTPS**, except for
`127.0.0.1`/`localhost` (see `android/app/src/main/res/xml/network_security_config.xml`).

| Scenario | Build flag |
|---|---|
| Backend deployed with HTTPS | `--dart-define=API_BASE_URL=https://api.example.com` |
| Testing a release build on your own phone over USB (`adb reverse`) | `--dart-define=API_TARGET=usb` |

A release build that points at `http://10.0.2.2` or `http://192.168.x.x` cannot connect,
because Android blocks plain HTTP in release builds. Use a debug build for those cases.

## 4. Build

```powershell
cd mobile
flutter clean
flutter pub get
flutter build apk --release --dart-define=API_TARGET=usb
# or: flutter build apk --release --dart-define=API_BASE_URL=https://your-server
```

Output: `mobile\build\app\outputs\flutter-apk\app-release.apk`

Smaller downloads, one APK per CPU type:

```powershell
flutter build apk --release --split-per-abi --dart-define=API_TARGET=usb
```

Most modern phones need `app-arm64-v8a-release.apk`.

For the Play Store, build an App Bundle instead:
`flutter build appbundle --release --dart-define=API_BASE_URL=https://your-server`.

## 5. Check the signature and install

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\<version>\apksigner.bat" verify --print-certs `
  build\app\outputs\flutter-apk\app-release.apk
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

The certificate's `CN` should be the name you gave `keytool`, not `Android Debug`.

## 6. Versioning

The version comes from `mobile/pubspec.yaml` as `version: 1.0.0+1`, which means
`versionName+versionCode`. Increase the `+N` build number for every APK you share, because
Android refuses to install a lower or equal versionCode over an existing install.

## Release checklist

- [ ] All 7 quality gates pass.
- [ ] `key.properties` and the `.jks` file are **not** in `git status`.
- [ ] The APK was built with the intended `API_BASE_URL` or `API_TARGET`.
- [ ] `apksigner verify` shows your certificate, not the debug one.
- [ ] Tested on a real phone: register, login, units, topic, tutor, practice, progress.
- [ ] The backend runs with a real `SECRET_KEY` and `GEMINI_API_KEY`, and `.env` was never
      committed.
