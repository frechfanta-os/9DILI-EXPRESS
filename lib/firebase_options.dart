// File generated for 9DILI EXPRESS (dili-express).
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return android;
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCUbk_KE1NJ2QMeGhUvg882EMgFrXB6Qi0',
    appId: '1:273784230349:web:dili_express_web',
    messagingSenderId: '273784230349',
    projectId: 'dili-express',
    authDomain: 'dili-express.firebaseapp.com',
    storageBucket: 'dili-express.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCUbk_KE1NJ2QMeGhUvg882EMgFrXB6Qi0',
    appId: '1:273784230349:android:1317b52fa41defee973484',
    messagingSenderId: '273784230349',
    projectId: 'dili-express',
    storageBucket: 'dili-express.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCUbk_KE1NJ2QMeGhUvg882EMgFrXB6Qi0',
    appId: '1:273784230349:ios:com_ghdinteractivestudio_dili_express',
    messagingSenderId: '273784230349',
    projectId: 'dili-express',
    storageBucket: 'dili-express.firebasestorage.app',
    iosBundleId: 'com.ghdinteractivestudio.dili_express',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCUbk_KE1NJ2QMeGhUvg882EMgFrXB6Qi0',
    appId: '1:273784230349:ios:com_ghdinteractivestudio_dili_express',
    messagingSenderId: '273784230349',
    projectId: 'dili-express',
    storageBucket: 'dili-express.firebasestorage.app',
    iosBundleId: 'com.ghdinteractivestudio.dili_express',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyCUbk_KE1NJ2QMeGhUvg882EMgFrXB6Qi0',
    appId: '1:273784230349:web:dili_express_windows',
    messagingSenderId: '273784230349',
    projectId: 'dili-express',
    storageBucket: 'dili-express.firebasestorage.app',
  );
}
