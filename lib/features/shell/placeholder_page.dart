import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Page vide du lot 0, remplacée page par page dans les lots suivants.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: Center(
        child: Text('À venir', style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}
