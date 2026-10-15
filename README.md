# BGI Pricing — mobile (Flutter)

Android / iOS client for the BGI Pricing API (same features as the web app:
dashboard, quinzaines, cotations, taux, and for admins configurations, import,
users, audit, Excel/PDF exports).

## Network

The app calls the **API** directly (not the web UI port):

| Environment | URL |
|---|---|
| Production (via VPN) | `http://10.10.2.10:3000` (default) |
| Android emulator → local API | `http://10.0.2.2:3000` |

The address can be changed from the login screen (« Serveur ») or *Plus › Serveur*.
Connect the company VPN on the phone before opening the app. Cleartext HTTP is
allowed (`usesCleartextTraffic` on Android, ATS exception on iOS) because the
API is served over HTTP on the internal network.

## Development

```bash
flutter pub get
flutter analyze
flutter test test
flutter run            # device or emulator
```

Launcher icons are generated from code:

```bash
flutter test tool/icon_gen_test.dart   # renders assets/icon/*.png
dart run flutter_launcher_icons        # writes Android/iOS icon sets
```

## Android release

```bash
flutter build apk --release
# -> build/app/outputs/flutter-apk/app-release.apk
```

The release build is currently signed with the debug key, which is fine for
internal sideloading. Before publishing on Google Play, create an upload
keystore and configure `signingConfigs` in `android/app/build.gradle.kts`.

## iOS release

iOS builds require macOS with Xcode (or a cloud Mac such as Codemagic).

On a Mac:

```bash
flutter pub get
cd ios && pod install && cd ..        # generates the Podfile on first run
open ios/Runner.xcworkspace           # set the Team in Signing & Capabilities
flutter build ipa --release           # -> build/ios/ipa/*.ipa
```

Then upload with Xcode Organizer or Transporter to TestFlight, or distribute
ad hoc / via Apple Business Manager.

With Codemagic: connect the repository, add an App Store Connect API key
integration named `BGI App Store Connect`, and run the `ios-release` workflow
from `codemagic.yaml` (bundle id `ma.bgipetroleum.bgiPricingMobile`).
