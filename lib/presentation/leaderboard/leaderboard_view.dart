import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/friends_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/leaderboard_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/leaderboard_entry.dart';
import 'package:defi_kilimandjaro/presentation/leaderboard/widgets/display_name_prompt.dart';
import 'package:defi_kilimandjaro/presentation/leaderboard/widgets/leaderboard_tile.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Clé SharedPreferences : true si le prompt displayName a déjà été affiché.
const String kSeenDisplayNamePromptKey = 'seen_displayname_prompt';

/// Écran classement — 2 tabs : GLOBAL (top-100) + AMIS (following).
///
/// Affiche le prompt displayName lors du premier accès si non encore défini.
/// Bouton "+" en action pour ajouter des amis via QR.
class LeaderboardView extends ConsumerStatefulWidget {
  const LeaderboardView({super.key});

  @override
  ConsumerState<LeaderboardView> createState() => _LeaderboardViewState();
}

class _LeaderboardViewState extends ConsumerState<LeaderboardView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _promptChecked = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_promptChecked) {
      _promptChecked = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _checkDisplayNamePrompt(),
      );
    }
  }

  Future<void> _checkDisplayNamePrompt() async {
    if (!mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final profile = await ref.read(profileRepositoryProvider).fetchProfile(uid);
    if (profile?.displayName?.isNotEmpty ?? false) return;

    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(kSeenDisplayNamePromptKey) ?? false) return;

    // Marquer comme vu avant d'afficher (évite double-prompt si pop rapide).
    await prefs.setBool(kSeenDisplayNamePromptKey, true);

    if (!mounted) return;
    final (result, name) = await DisplayNamePromptDialog.show(context);

    if (result == DisplayNamePromptResult.confirmed && name != null) {
      await ref.read(profileRepositoryProvider).updateDisplayName(uid, name);
    }
  }

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.vertForet,
      appBar: AppBar(
        backgroundColor: AppColors.vertForet,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          color: AppColors.orSoleil,
          onPressed: () => context.pop(),
          tooltip: 'common.back'.tr(),
        ),
        title: Text(
          'leaderboard.title'.tr(),
          style: AppTypography.bebas(size: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            color: AppColors.orSoleil,
            tooltip: 'friends.add_title'.tr(),
            onPressed: () => context.push(AppRoutes.addFriend),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.orSoleil,
            labelStyle: AppTypography.bebas(size: 14),
            unselectedLabelColor: AppColors.texteTertiaire,
            tabs: [
              Tab(text: 'leaderboard.tab_global'.tr()),
              Tab(text: 'leaderboard.tab_friends'.tr()),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _GlobalTab(myUid: _myUid),
          _FriendsTab(myUid: _myUid),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab GLOBAL
// ---------------------------------------------------------------------------

class _GlobalTab extends ConsumerWidget {
  const _GlobalTab({required this.myUid});
  final String? myUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncEntries = ref.watch(globalLeaderboardProvider);
    final myRankAsync = myUid != null
        ? ref.watch(myRankProvider(myUid!))
        : null;

    return asyncEntries.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.orSoleil),
      ),
      error: (e, _) => _ErrorState(message: e.toString()),
      data: (entries) {
        final inList = entries.any((e) => e.uid == myUid);

        return RefreshIndicator(
          color: AppColors.orSoleil,
          backgroundColor: AppColors.boisFonce,
          onRefresh: () async => ref.invalidate(globalLeaderboardProvider),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Header sticky : mon rang si hors top-100 visible.
              if (!inList && myUid != null)
                SliverToBoxAdapter(
                  child: _MyRankHeader(myUid: myUid!, rankAsync: myRankAsync),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((_, i) {
                    final entry = entries[i];
                    return LeaderboardTile(
                      entry: entry,
                      isMe: entry.uid == myUid,
                    );
                  }, childCount: entries.length),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MyRankHeader extends ConsumerWidget {
  const _MyRankHeader({required this.myUid, required this.rankAsync});
  final String myUid;
  final AsyncValue<LeaderboardEntry?>? rankAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = rankAsync?.value;
    if (entry == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.orSoleil.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.orSoleil, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: AppColors.orSoleil, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'leaderboard.my_rank_label'.tr(
                args: ['#${entry.rank}', entry.altitudeLabel],
              ),
              style: AppTypography.bebas(size: 14, color: AppColors.orSoleil),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab AMIS
// ---------------------------------------------------------------------------

class _FriendsTab extends ConsumerWidget {
  const _FriendsTab({required this.myUid});
  final String? myUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (myUid == null) {
      return Center(
        child: Text('error.generic'.tr(), style: AppTypography.crimson()),
      );
    }

    final asyncEntries = ref.watch(friendsLeaderboardProvider(myUid!));

    return asyncEntries.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.orSoleil),
      ),
      error: (e, _) => _ErrorState(message: e.toString()),
      data: (entries) {
        // entries.length <= 1 = uniquement moi-même → pas d'amis.
        if (entries.length <= 1) {
          return _FriendsEmptyState(
            onAddFriend: () => context.push(AppRoutes.addFriend),
          );
        }

        return RefreshIndicator(
          color: AppColors.orSoleil,
          backgroundColor: AppColors.boisFonce,
          onRefresh: () async =>
              ref.invalidate(friendsLeaderboardProvider(myUid!)),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final entry = entries[i];
              final isMe = entry.uid == myUid;
              return LeaderboardTile(
                entry: entry,
                isMe: isMe,
                onRemove: isMe
                    ? null
                    : () => _removeFriend(context, ref, myUid!, entry),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _removeFriend(
    BuildContext context,
    WidgetRef ref,
    String myUid,
    LeaderboardEntry entry,
  ) async {
    try {
      await ref.read(friendsRepositoryProvider).removeFriend(myUid, entry.uid);
      ref.invalidate(friendsLeaderboardProvider(myUid));
    } on Exception catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('error.generic'.tr(), style: AppTypography.bebas()),
          backgroundColor: AppColors.rouge,
        ),
      );
      debugPrint('removeFriend error: $e');
    }
  }
}

class _FriendsEmptyState extends StatelessWidget {
  const _FriendsEmptyState({required this.onAddFriend});
  final VoidCallback onAddFriend;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.group_outlined,
              color: AppColors.orSoleil,
              size: 52,
            ),
            const SizedBox(height: 16),
            Text(
              'friends.empty'.tr(),
              style: AppTypography.bebas(size: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'friends.empty_sub'.tr(),
              style: AppTypography.crimson(
                size: 13,
                color: AppColors.texteSecondaire,
                style: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAddFriend,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.vertClair,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.qr_code_scanner, color: AppColors.ivoire),
              label: Text(
                'friends.add_via_qr'.tr(),
                style: AppTypography.bebas(size: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared error widget
// ---------------------------------------------------------------------------

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, color: AppColors.rouge, size: 40),
            const SizedBox(height: 12),
            Text(
              'error.network'.tr(),
              style: AppTypography.bebas(color: AppColors.rouge),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: AppTypography.crimson(
                size: 11,
                color: AppColors.texteTertiaire,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
