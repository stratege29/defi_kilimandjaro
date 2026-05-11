import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Résultat du prompt de saisie du displayName.
enum DisplayNamePromptResult {
  /// L'utilisateur a validé un nom (3–20 chars).
  confirmed,

  /// L'utilisateur a choisi de rester anonyme.
  anonymous,
}

/// Dialog bloquant de saisie du nom de grimpeur.
///
/// Affiché une seule fois par session (contrôle via SharedPreferences dans
/// LeaderboardView). Retourne `(result, name?)`.
class DisplayNamePromptDialog extends StatefulWidget {
  const DisplayNamePromptDialog({super.key});

  /// Lance le dialog et retourne `(result, name)`.
  /// `name` n'est non-null que si result == confirmed.
  static Future<(DisplayNamePromptResult, String?)> show(
    BuildContext context,
  ) async {
    final result = await showDialog<(DisplayNamePromptResult, String?)>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DisplayNamePromptDialog(),
    );
    return result ?? (DisplayNamePromptResult.anonymous, null);
  }

  @override
  State<DisplayNamePromptDialog> createState() =>
      _DisplayNamePromptDialogState();
}

class _DisplayNamePromptDialogState extends State<DisplayNamePromptDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      (DisplayNamePromptResult.confirmed, _controller.text.trim()),
    );
  }

  void _stayAnonymous() {
    Navigator.of(context).pop(
      (DisplayNamePromptResult.anonymous, null),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.boisFonce,
      title: Text(
        'leaderboard.prompt_title'.tr(),
        style: AppTypography.bebas(size: 20),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'leaderboard.prompt_body'.tr(),
              style: AppTypography.crimson(
                size: 13,
                color: AppColors.ivoire.withValues(alpha: 0.75),
                style: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              maxLength: 20,
              textCapitalization: TextCapitalization.words,
              autofocus: true,
              style: AppTypography.bebas(size: 18),
              decoration: InputDecoration(
                counterStyle: AppTypography.crimson(
                  size: 11,
                  color: AppColors.ivoire.withValues(alpha: 0.5),
                ),
                hintText: 'leaderboard.prompt_hint'.tr(),
                hintStyle: AppTypography.crimson(
                  size: 14,
                  color: AppColors.ivoire.withValues(alpha: 0.4),
                ),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.bois),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.orSoleil),
                ),
                errorBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.rouge),
                ),
                focusedErrorBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.rouge),
                ),
                errorStyle: AppTypography.crimson(
                  size: 11,
                  color: AppColors.rouge,
                ),
              ),
              validator: (v) {
                final val = v?.trim() ?? '';
                if (val.length < 3) {
                  return 'leaderboard.prompt_error_min'.tr();
                }
                return null;
              },
              onFieldSubmitted: (_) => _confirm(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _stayAnonymous,
          child: Text(
            'leaderboard.prompt_anonymous'.tr(),
            style: AppTypography.crimson(
              size: 13,
              color: AppColors.ivoire.withValues(alpha: 0.7),
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _confirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.vertClair,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: Text(
            'leaderboard.prompt_validate'.tr(),
            style: AppTypography.bebas(size: 15),
          ),
        ),
      ],
    );
  }
}
