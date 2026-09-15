import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/pairing/pairing_providers.dart';

/// Lets the user create a new sync group (and see the code to share
/// with their other devices) or join an existing one by entering a
/// code. See spec: "No accounts — pairing code as the auth mechanism."
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _codeController = TextEditingController();
  String? _createdCode;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    setState(() => _error = null);
    try {
      final code = await ref.read(pairingProvider.notifier).createGroup();
      setState(() => _createdCode = code);
    } catch (_) {
      setState(() => _error = 'Could not create a sync group. Try again.');
    }
  }

  Future<void> _joinGroup() async {
    setState(() => _error = null);
    try {
      await ref
          .read(pairingProvider.notifier)
          .joinGroup(_codeController.text.trim().toUpperCase());
    } catch (_) {
      setState(
        () => _error = 'That code wasn\'t found. Check it and try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync devices')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_createdCode != null) ...[
              Text('Your pairing code: $_createdCode'),
              const Text('Enter this on your other device to sync.'),
              const SizedBox(height: 24),
            ] else ...[
              ElevatedButton(
                onPressed: _createGroup,
                child: const Text('Create a new sync group'),
              ),
              const SizedBox(height: 24),
            ],
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(labelText: 'Pairing code'),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _joinGroup,
              child: const Text('Join with a code'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
