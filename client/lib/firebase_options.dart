import 'package:firebase_core/firebase_core.dart';

// Keep Android Firebase options explicit for both the main isolate and the
// FCM background isolate; data-only pushes need Dart to initialize reliably.
const FirebaseOptions androidFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyAZAQ69JCgldJULTCxUz5jtC_DxKevCY0',
  appId: '1:907469003345:android:e9411583b33fec0dd6f670',
  messagingSenderId: '907469003345',
  projectId: 'altakhfidalsh',
  storageBucket: 'altakhfidalsh.firebasestorage.app',
);
