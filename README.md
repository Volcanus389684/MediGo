# MediGo

MediGo is a Flutter app for a bus-mounted medicine dispenser. A patient signs in, scans or enters the dispenser address, selects available medicines, and submits a request. The app records the request in Firebase, reduces inventory, and sends a command to the ESP32 over the local WiFi network. Operators manage stock and view request history.

This is a prototype. Do not use it to make medical decisions or dispense medicine without appropriate clinical, hardware, and safety review.

## What You Need

- Windows 10/11, macOS, or Linux
- Git
- Flutter SDK 3.13 or newer
- Android Studio with Android SDK and an emulator, or a physical Android phone
- A Firebase account
- For real hardware testing: an ESP32 running the MediGo HTTP server supplied by the IoT team

The project uses Firebase Authentication, Realtime Database, Firebase Storage, QR scanning, and HTTP networking.

## Clone The Project

```powershell
git clone <YOUR_GITHUB_REPOSITORY_URL>
cd MediGo
flutter doctor
flutter devices
```

If `flutter` is not recognized on Windows, use the full SDK path:

```powershell
& "C:\Users\YOUR_NAME\flutter-sdk\bin\flutter.bat" doctor
```

## Install Android Studio

1. Install Android Studio from https://developer.android.com/studio.
2. Open Android Studio and install the Android SDK, SDK Platform, SDK Build-Tools, and Android Emulator.
3. Open **Device Manager** and create an emulator, or connect a physical phone with USB debugging enabled.
4. Run:

```powershell
flutter doctor --android-licenses
flutter doctor
```

Accept the Android licenses. For a physical phone, enable Developer Options and USB debugging, connect it by USB, and accept the authorization dialog on the phone.

## Configure Firebase

### Create or use a Firebase project

1. Open https://console.firebase.google.com/.
2. Create a project or use the project assigned to your team.
3. Add an Android app with package name `com.medigo.medigo`.
4. Download `google-services.json`.
5. Put it at `android/app/google-services.json`.

This file is ignored by Git. Each developer downloads their own copy from Firebase. For iOS, register bundle ID `com.medigo.medigo`, download `GoogleService-Info.plist`, and place it in `ios/Runner/`.

### Android setup checklist

After placing `google-services.json`, confirm these details before running the app:

- The Android package name in Firebase is exactly `com.medigo.medigo`.
- The file is at `android/app/google-services.json`, not only in the project root.
- The Android device has Google Play services and internet access.
- USB debugging is enabled if using a physical phone.
- The Firebase project used by `google-services.json` matches the values in `lib/firebase_options.dart`.

Do not edit `android/local.properties` by hand unless Flutter created it. It contains the local Android SDK path and is different on every computer.

### Enable Authentication

1. Open **Build > Authentication** in Firebase Console.
2. Select **Get started**.
3. Open **Sign-in method**.
4. Enable **Email/Password**.

New accounts are customer accounts. To make an account an operator, find its UID in Authentication and set this Realtime Database value:

```text
users/<uid>/role = operator
```

#### Create an operator account manually

The app does not show an operator registration button. Create operator access only from Firebase Console:

1. Open **Build > Authentication > Users**.
2. Select **Add user**.
3. Enter the operator's email address and a temporary password of at least 6 characters.
4. Select **Add user**.
5. Copy the new user's **User UID**. It is a long string such as `abc123...`.
6. Open **Build > Realtime Database > Data**.
7. Create or open the `users` node.
8. Add a child whose key is the copied UID.
9. Add this child below that UID:

```text
users
└── <operator-uid>
		└── role: operator
```

You can also add the operator profile fields:

```json
{
	"email": "operator@example.com",
	"fullName": "Bus Operator",
	"role": "operator"
}
```

10. In the app, sign out of the patient account and sign in with the operator email and temporary password.
11. After confirming access, change the temporary password through the Firebase Authentication user menu or use a password-reset flow.

If the operator sees the patient screens, check that the UID in `users/<uid>` is exactly the UID shown in Firebase Authentication and that `role` is exactly lowercase `operator`.

### Enable Realtime Database

1. Open **Build > Realtime Database**.
2. Select **Create Database** and choose the required region.
3. Use test mode only for local development.
4. Before production, replace test rules with authenticated rules reviewed by your team.

For a quick prototype test, the database may use Firebase test mode. Test mode allows unauthenticated access and must not be used for a public deployment. A production rules design should at minimum restrict patient data to signed-in users, restrict operator inventory changes to users whose role is `operator`, and allow the ESP32 only the device paths it needs. Have the Firebase owner review and publish the final rules in **Realtime Database > Rules**.

The app uses these paths:

```text
users/<uid>
medicines/<position>
dispensing/<requestId>
prescriptions/<prescriptionId>
device/esp/address
device/command
```

### Enable Storage

Enable Firebase Storage if prescription images must be uploaded. Configure Storage rules before production use.

If Storage is not enabled, the app can still show a local prescription preview, but an operator may not be able to view the uploaded image from another device. For team testing, open **Storage > Get started**, choose the same Firebase region policy as the project, and use test mode only temporarily.

### Firebase manual setup summary

The Firebase Console setup order is:

1. Create/select the Firebase project.
2. Add the Android app with package `com.medigo.medigo`.
3. Download `google-services.json` into `android/app/`.
4. Enable **Authentication > Email/Password**.
5. Create at least one operator user manually and add `users/<uid>/role = operator`.
6. Create **Realtime Database** and choose the project region.
7. Enable **Storage** if shared prescription images are required.
8. Review Database and Storage rules before using real patient data.
9. Run `flutter pub get`, `flutter analyze`, and `flutter run`.

`lib/firebase_options.dart` contains the project settings used by Flutter. For a different Firebase project, regenerate or replace it with the FlutterFire configuration for that project. Never commit Firebase service-account keys, Admin SDK keys, or private API credentials.

## Install Dependencies And Run

```powershell
flutter pub get
flutter analyze
flutter run
```

For a particular device:

```powershell
flutter devices
flutter run -d <device-id>
```

The first Android build can take several minutes. If the Dart VM reports out-of-memory, close Android Studio/emulators and other heavy applications, then run the command again.

## First App Test

1. Register a customer account.
2. Complete onboarding.
3. Open the patient home screen.
4. Use the QR icon to pair a dispenser, or type an address manually.
5. Sign in separately with an operator account.
6. Open **Inventory**, clear old inventory if needed, and set up compartments 1-7.
7. Return to the patient account and select medicines with stock greater than zero.
8. Set quantities and submit.
9. Confirm the result page shows every medicine, the command, and ESP delivery status.
10. Check patient **History** and operator **Requests**.

## Inventory Setup

The operator maps each medicine to a physical ESP32 compartment:

```text
Position 1 -> ESP32 position 1
Position 2 -> ESP32 position 2
...
Position 7 -> ESP32 position 7
```

When medicine is physically loaded, open **Inventory**, select the compartment, and enter the medicine name, strength, stock count, and prescription requirement. Patient selection only shows medicines with stock greater than zero. A successful request atomically subtracts the requested quantity from Firebase inventory.

## ESP32 Command Format

The current app command is a 14-character ASCII string, not raw binary bytes. It contains seven two-digit decimal quantities:

```text
P1 P2 P3 P4 P5 P6 P7
```

`00` means no units. For example:

```text
02000001000000
```

means:

```text
P1 = 02  -> dispense 2 units from position 1
P2 = 00  -> do nothing
P3 = 00  -> do nothing
P4 = 01  -> dispense 1 unit from position 4
P5 = 00
P6 = 00
P7 = 00
```

The app sends:

```text
GET http://<ESP_IP>/dispense?command=<14-character-command>
```

The connection test sends:

```text
GET http://<ESP_IP>/status
```

The IoT team must implement these endpoints, or update `lib/services/esp_connection_service.dart` to match their final protocol. The original ESP32 sketch only reads DIP switches; it must be extended with WiFi and an HTTP server before real delivery can work.

## Generate A Test QR Code

Until the bus has a real ESP32, use a QR generator such as https://www.qrcode-monkey.com/:

1. Choose a plain text QR code.
2. Enter a test IP, for example `192.168.1.50`.
3. Generate the QR code and display it on a laptop screen.
4. Open the app QR icon and scan it.

A fake IP should produce a connection failure. That tests QR reading and failure handling. A MAC address such as `AA:BB:CC:DD:EE:FF` identifies hardware but cannot be used directly for an HTTP request; the QR should contain the ESP32's reachable IP or hostname.

## Simulate An ESP32 On Your Laptop

The phone and laptop must use the same WiFi network. Find the laptop address in PowerShell:

```powershell
ipconfig
```

Use the active adapter's **IPv4 Address**, such as `192.168.1.23`. Do not use `127.0.0.1`; that points to the phone itself.

The simulator code is already included in this repository at `tools/medigo_esp_simulator.py`. You do not need to create or copy a Python file.

Open a second PowerShell window, go to the project folder, and run:

```powershell
cd C:\Users\YOUR_NAME\Desktop\MediGo
python .\tools\medigo_esp_simulator.py
```

The simulator listens on port `8080`, so create a QR containing your laptop address with the port, for example `192.168.1.23:8080`. Scan it in MediGo and tap **Test connection now**. The app should show a successful `/status` response. Submit medicines afterward; this PowerShell window prints the received 14-character command.

If Windows Firewall asks, allow Python through private networks. Keep the simulator window open while testing. Stop it with `Ctrl+C`.

## GitHub Checklist

Before pushing:

```powershell
flutter analyze
git status
git diff -- .gitignore README.md lib/main.dart lib/services
```

Do not commit:

- `build/`
- `.dart_tool/`
- `android/local.properties`
- `google-services.json`
- `GoogleService-Info.plist`
- keystores or service-account JSON files
- Firebase Admin credentials

The repository ignores Flutter build output and local Android configuration. Each teammate must run the Firebase setup steps locally after cloning.
#   M e d i G o  
 