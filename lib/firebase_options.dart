import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static const String projectId = 'medigo-app-a4a4c';
  static const String databaseUrl =
      'https://medigo-app-a4a4c-default-rtdb.asia-southeast1.firebasedatabase.app';
  static const String storageBucket = 'medigo-app-a4a4c.firebasestorage.app';

  static FirebaseOptions get currentPlatform {
    return const FirebaseOptions(
      apiKey: 'AIzaSyD1mY-iu14TPAh5YgoM6a6Dail0fSci0V0',
      appId: '1:12309857376:android:f09526fd916edf888eef05',
      messagingSenderId: '12309857376',
      projectId: projectId,
      databaseURL: databaseUrl,
      storageBucket: 'medigo-app-a4a4c.firebasestorage.app',
      iosBundleId: 'com.medigo.medigo',
    );
  }
}
