// scripts/setup_pocketbase.dart
//
// One-time setup: creates the sync_groups auth collection and the six
// base sync collections via PocketBase's admin import API. Safe to
// re-run — import replaces collections by name, it doesn't duplicate
// them. Run with:
//   dart run scripts/setup_pocketbase.dart <baseUrl> <superuserEmail> <superuserPassword>
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln(
      'Usage: dart run scripts/setup_pocketbase.dart <baseUrl> <email> <password>',
    );
    exitCode = 64;
    return;
  }
  final baseUrl = args[0];
  final email = args[1];
  final password = args[2];
  final client = HttpClient();

  Future<String> authenticate() async {
    final request = await client.postUrl(
      Uri.parse('$baseUrl/api/collections/_superusers/auth-with-password'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'identity': email, 'password': password}));
    final response = await request.close();
    final body = jsonDecode(await response.transform(utf8.decoder).join());
    if (response.statusCode != 200) {
      throw StateError('Auth failed (${response.statusCode}): $body');
    }
    return body['token'] as String;
  }

  Map<String, Object?> baseCollection(String name) => {
    'name': name,
    'type': 'base',
    'fields': [
      {'name': 'entity_id', 'type': 'text', 'required': true},
      {'name': 'sync_group', 'type': 'text', 'required': true},
      {'name': 'updated_at', 'type': 'text', 'required': true},
      {'name': 'deleted', 'type': 'bool', 'required': false},
      {'name': 'data', 'type': 'json', 'required': true},
    ],
    'indexes': [
      'CREATE INDEX idx_${name}_sync_group_updated ON $name (sync_group, updated_at)',
      'CREATE UNIQUE INDEX idx_${name}_entity ON $name (entity_id)',
    ],
    'listRule': 'sync_group = @request.auth.id',
    'viewRule': 'sync_group = @request.auth.id',
    'createRule': 'sync_group = @request.auth.id',
    'updateRule': 'sync_group = @request.auth.id',
    'deleteRule': 'sync_group = @request.auth.id',
  };

  const collectionNames = [
    'tasks',
    'categories',
    'templates',
    'template_blocks',
    'saved_searches',
    'day_blocks',
  ];

  final token = await authenticate();
  final request = await client.putUrl(
    Uri.parse('$baseUrl/api/collections/import'),
  );
  request.headers.contentType = ContentType.json;
  request.headers.set('Authorization', token);
  request.write(
    jsonEncode({
      'collections': [
        {
          'name': 'sync_groups',
          'type': 'auth',
          'fields': [
            {'name': 'username', 'type': 'text', 'required': true},
          ],
          'indexes': [
            'CREATE UNIQUE INDEX idx_sync_groups_username ON sync_groups (username)',
          ],
          'passwordAuth': {'enabled': true, 'identityFields': ['username']},
        },
        for (final name in collectionNames) baseCollection(name),
      ],
      'deleteMissing': false,
    }),
  );
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200 && response.statusCode != 204) {
    throw StateError('Import failed (${response.statusCode}): $body');
  }
  stdout.writeln('PocketBase collections created.');
  client.close();
}
