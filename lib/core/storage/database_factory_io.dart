import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

DatabaseFactory createDatabaseFactory() => databaseFactoryIo;

Future<String> databasePath() async {
  final directory = await getApplicationDocumentsDirectory();
  return path.join(directory.path, 'taskframe.db');
}
