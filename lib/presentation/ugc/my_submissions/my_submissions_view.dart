import 'package:defi_kilimandjaro/data/repositories/submission_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette_submission.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Liste des soumissions de l'utilisateur courant avec leur statut.
class MySubmissionsView extends ConsumerWidget {
  const MySubmissionsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mySubmissionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes propositions')),
      body: async.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucune soumission pour le moment.\n'
                  'Propose ta première devinette !',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _Tile(submission: items[i]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.submission});
  final DevinetteSubmission submission;

  @override
  Widget build(BuildContext context) {
    final color = switch (submission.status) {
      SubmissionStatus.pending => Colors.amber,
      SubmissionStatus.preApproved => Colors.lightBlue,
      SubmissionStatus.approved => Colors.green,
      SubmissionStatus.rejected => Colors.red,
      SubmissionStatus.flagged => Colors.deepOrange,
    };
    final label = switch (submission.status) {
      SubmissionStatus.pending => 'En attente',
      SubmissionStatus.preApproved => 'Pré-approuvée',
      SubmissionStatus.approved => 'Publiée',
      SubmissionStatus.rejected => 'Refusée',
      SubmissionStatus.flagged => 'Signalée',
    };
    return ListTile(
      title: Text(submission.answer),
      subtitle: Text(
        '${submission.world} • ${submission.lang} • '
        'Niveau ${submission.difficulty}\n${submission.riddle}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: Chip(
        label: Text(label),
        backgroundColor: color.withValues(alpha: 0.2),
        side: BorderSide(color: color),
      ),
    );
  }
}
