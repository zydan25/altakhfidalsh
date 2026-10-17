import 'package:flutter/material.dart';
import 'src/ui/flask_storefront.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Client2WebApp());
}

class Client2WebApp extends StatelessWidget {
  const Client2WebApp({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'التخفيض الصح',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        primaryColor: Colors.black,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: FlaskStorefront(),
    );
  }
}
