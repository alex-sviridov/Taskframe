import 'package:sembast/sembast.dart';

/// Never selected at runtime — [database_factory.dart]'s conditional
/// export always resolves to either the io or web variant. Exists only
/// as the default branch conditional exports require.
DatabaseFactory createDatabaseFactory() =>
    throw UnsupportedError('No sembast factory available on this platform');

Future<String> databasePath() async =>
    throw UnsupportedError('No sembast factory available on this platform');
