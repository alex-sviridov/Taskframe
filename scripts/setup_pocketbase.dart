// scripts/setup_pocketbase.dart
//
// One-time setup: creates the users auth collection and the six
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
    final body = jsonDecode(
      await response.transform(utf8.decoder).join(),
    ) as Map<String, dynamic>;
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
      {'name': 'owner', 'type': 'text', 'required': true},
      {'name': 'updated_at', 'type': 'text', 'required': true},
      {'name': 'deleted', 'type': 'bool', 'required': false},
      {'name': 'data', 'type': 'json', 'required': true},
      // PocketBase no longer auto-adds `created`/`updated` unless they're
      // explicitly declared as autodate fields. `updated` is what
      // PocketBaseSyncClient.listChangedSince/SyncEngine._pull use as the
      // pull cursor (server-managed, immune to client clock skew) — see
      // the sync design doc's data flow.
      {'name': 'created', 'type': 'autodate', 'onCreate': true},
      {
        'name': 'updated',
        'type': 'autodate',
        'onCreate': true,
        'onUpdate': true,
      },
    ],
    'indexes': [
      'CREATE INDEX idx_${name}_owner_updated ON $name (owner, updated_at)',
      'CREATE UNIQUE INDEX idx_${name}_entity ON $name (owner, entity_id)',
    ],
    'listRule': 'owner = @request.auth.id',
    'viewRule': 'owner = @request.auth.id',
    'createRule': 'owner = @request.auth.id',
    'updateRule': 'owner = @request.auth.id',
    'deleteRule': 'owner = @request.auth.id',
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
          'name': 'users',
          'type': 'auth',
          // Real accounts: standard PocketBase auth-collection posture, unlike
          // the old pairing-code collection — public self-registration
          // (createRule: '' — anyone can sign up, same posture PocketBase
          // ships by default for a fresh auth collection's create), email as
          // the identity field, and PocketBase's default password rules (min
          // 8) instead of the old 6-char minimum that only existed to match
          // 6-character pairing codes.
          'createRule': '',
          'fields': [
            {'name': 'email', 'type': 'email', 'required': true},
            {
              'name': 'password',
              'type': 'password',
              'required': true,
              'min': 8,
            },
          ],
          'passwordAuth': {
            'enabled': true,
            'identityFields': ['email'],
          },
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
