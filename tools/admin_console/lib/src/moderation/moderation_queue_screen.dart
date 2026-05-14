import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kilimandjaro_admin/src/moderation/submission.dart';

/// Lists submissions whose curator decision is `review` — i.e. the human-
/// moderation queue. Sorted by score descending so the strongest candidates
/// are seen first.
class ModerationQueueScreen extends StatefulWidget {
  const ModerationQueueScreen({super.key});

  @override
  State<ModerationQueueScreen> createState() => _ModerationQueueScreenState();
}

class _ModerationQueueScreenState extends State<ModerationQueueScreen> {
  String _filter = 'review';

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    return FirebaseFirestore.instance
        .collection('submissions')
        .where('status', isEqualTo: _filter)
        .orderBy('score', descending: true)
        .limit(100)
        .snapshots();
  }

  Future<void> _setStatus(Submission s, String status) async {
    await FirebaseFirestore.instance
        .collection('submissions')
        .doc(s.id)
        .update({
      'status': status,
      'moderatedAt': FieldValue.serverTimestamp(),
      'moderatedBy': FirebaseAuth.instance.currentUser?.uid,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('File de modération'),
        actions: [
          DropdownButton<String>(
            value: _filter,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'review', child: Text('À modérer')),
              DropdownMenuItem(value: 'approve', child: Text('Approuvées')),
              DropdownMenuItem(value: 'reject', child: Text('Rejetées')),
              DropdownMenuItem(value: 'pending', child: Text('En attente LLM')),
            ],
            onChanged: (v) => setState(() => _filter = v ?? 'review'),
          ),
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erreur: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('File vide.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final s = Submission.fromDoc(docs[i]);
              return _SubmissionCard(
                submission: s,
                onApprove: () => _setStatus(s, 'approve'),
                onReject: () => _setStatus(s, 'reject'),
              );
            },
          );
        },
      ),
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({
    required this.submission,
    required this.onApprove,
    required this.onReject,
  });

  final Submission submission;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat.yMd().add_Hm();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ScoreChip(score: submission.score),
                const SizedBox(width: 8),
                Text(
                  '${submission.country} · ${submission.locale} · diff. ${submission.difficulty}/5',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const Spacer(),
                Text(
                  submission.createdAt == null
                      ? '—'
                      : df.format(submission.createdAt!),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(submission.question, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Réponse: ${submission.answer}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (submission.proverb != null) ...[
              const SizedBox(height: 4),
              Text('Proverbe: ${submission.proverb}',
                  style: const TextStyle(fontStyle: FontStyle.italic)),
            ],
            if (submission.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: submission.tags
                    .map((t) => Chip(label: Text(t), visualDensity: VisualDensity.compact))
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (submission.curatedBy != null)
                  Text('Curator: ${submission.curatedBy}',
                      style: Theme.of(context).textTheme.labelSmall),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close, color: Colors.redAccent),
                  label: const Text('Rejeter'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check),
                  label: const Text('Approuver'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.score});
  final int score;

  Color _color() {
    if (score >= 80) return Colors.green;
    if (score >= 55) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color().withValues(alpha: 0.18),
        border: Border.all(color: _color()),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$score/100',
          style: TextStyle(color: _color(), fontWeight: FontWeight.w700)),
    );
  }
}
