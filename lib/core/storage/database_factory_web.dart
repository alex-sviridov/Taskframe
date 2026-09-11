import 'package:sembast/sembast.dart';
import 'package:sembast_web/sembast_web.dart';

DatabaseFactory createDatabaseFactory() => databaseFactoryWeb;

Future<String> databasePath() async => 'taskframe.db';
