// lib/features/account/widgets/account_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/account/account_providers.dart';

/// Lets a guest register a new account or log into an existing one; once
/// logged in, shows the account's email and a way to log out. See spec:
/// account-based sync replaces the pairing-code identity model.
class AccountScreen extends ConsumerStatefulWidget {
  /// Creates an [AccountScreen].
  const new({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegisterMode = true;
  String? _error;

  /// True while a register/log-in/re-authenticate call is in flight.
  /// Disables the submit button so a fast double-tap can't fire two
  /// concurrent calls — e.g. two `register()`s racing, where the second
  /// comes back "email already in use" even though the first succeeded.
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() {
      _error = null;
      _isSubmitting = true;
    });
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    try {
      if (_isRegisterMode) {
        await ref.read(accountProvider.notifier).register(email, password);
      } else {
        await ref.read(accountProvider.notifier).login(email, password);
      }
    } on Object {
      setState(
        () => _error = _isRegisterMode
            ? 'Could not register. That email may already be in use.'
            : 'Could not log in. Check your email and password.',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _reauthenticate(String email) async {
    if (_isSubmitting) return;
    setState(() {
      _error = null;
      _isSubmitting = true;
    });
    try {
      await ref
          .read(accountProvider.notifier)
          .login(email, _passwordController.text);
    } on Object {
      setState(() => _error = 'Could not log in. Check your password.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
      data: (state) {
        final email = state.email;
        if (email == null) return _buildForm(context);
        if (state.sessionExpired) return _buildExpiredSession(context, email);
        return _buildLoggedIn(email);
      },
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

  /// Shown instead of [_buildLoggedIn] when the stored session was
  /// rejected by the server (see [AccountState.sessionExpired]) — sync
  /// will keep failing silently otherwise, so this prompts for the
  /// password rather than claiming the account is still logged in.
  Widget _buildExpiredSession(BuildContext context, String email) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Your session for $email expired. Log in again to resume syncing.',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _passwordController,
        decoration: const InputDecoration(labelText: 'Password'),
        obscureText: true,
      ),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: _isSubmitting ? null : () => _reauthenticate(email),
        child: const Text('Log in again'),
      ),
      if (_error != null) ...[
        const SizedBox(height: 16),
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const SizedBox(height: 8),
      TextButton(onPressed: _logout, child: const Text('Log out instead')),
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
        onPressed: _isSubmitting ? null : _submit,
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
