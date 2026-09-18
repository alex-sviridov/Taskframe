// lib/features/account/widgets/account_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/account/account_providers.dart';

/// Lets a guest register a new account or log into an existing one; once
/// logged in, shows the account's email and a way to log out. See spec:
/// account-based sync replaces the pairing-code identity model.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegisterMode = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    try {
      if (_isRegisterMode) {
        await ref.read(accountProvider.notifier).register(email, password);
      } else {
        await ref.read(accountProvider.notifier).login(email, password);
      }
    } catch (_) {
      setState(
        () => _error = _isRegisterMode
            ? 'Could not register. That email may already be in use.'
            : 'Could not log in. Check your email and password.',
      );
    }
  }

  Future<void> _logout() async {
    await ref.read(accountProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider);
    final content = account.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _buildForm(context),
      data: (email) =>
          email != null ? _buildLoggedIn(email) : _buildForm(context),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < narrowBreakpoint) return content;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: content,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoggedIn(String email) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Logged in as $email'),
      const SizedBox(height: 24),
      ElevatedButton(onPressed: _logout, child: const Text('Log out')),
    ],
  );

  Widget _buildForm(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('Register')),
          ButtonSegment(value: false, label: Text('Log in')),
        ],
        selected: {_isRegisterMode},
        onSelectionChanged: (selected) =>
            setState(() => _isRegisterMode = selected.first),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _emailController,
        decoration: const InputDecoration(labelText: 'Email'),
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _passwordController,
        decoration: const InputDecoration(labelText: 'Password'),
        obscureText: true,
      ),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: _submit,
        child: Text(_isRegisterMode ? 'Register' : 'Log in'),
      ),
      if (_error != null) ...[
        const SizedBox(height: 16),
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ],
  );
}
