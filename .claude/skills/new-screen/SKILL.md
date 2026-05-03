---
name: new-screen
description: Scaffold a new Flutter screen following Kilimandjaro's Clean Architecture conventions. Creates the view, controller (Riverpod), widgets folder, route entry, and a widget test stub.
disable-model-invocation: true
---

# New Screen

Create a new Flutter screen for Kilimandjaro: $ARGUMENTS (e.g. "settings", "leaderboard", "duel_lobby")

## Steps

1. **Parse name** in snake_case. Reject if contains spaces, uppercase, or special chars.

2. **Create directory structure**:
   ```
   lib/presentation/<name>/
   ├── <name>_view.dart
   ├── <name>_controller.dart
   └── widgets/
       └── .gitkeep
   ```

3. **Generate `<name>_view.dart`** following the canonical pattern:
   ```dart
   import 'package:flutter/material.dart';
   import 'package:flutter_riverpod/flutter_riverpod.dart';
   import 'package:easy_localization/easy_localization.dart';
   import '<name>_controller.dart';

   class <PascalName>View extends ConsumerWidget {
     const <PascalName>View({super.key});

     @override
     Widget build(BuildContext context, WidgetRef ref) {
       final state = ref.watch(<camelName>ControllerProvider);
       return Scaffold(
         backgroundColor: Theme.of(context).colorScheme.surface,
         body: SafeArea(
           child: state.when(
             data: (data) => _<PascalName>Body(data: data),
             loading: () => const Center(child: CircularProgressIndicator()),
             error: (e, s) => Center(child: Text('error.generic'.tr())),
           ),
         ),
       );
     }
   }

   class _<PascalName>Body extends StatelessWidget {
     const _<PascalName>Body({required this.data});
     final dynamic data; // TODO: replace with proper type
     @override
     Widget build(BuildContext context) => const SizedBox.shrink();
   }
   ```

4. **Generate `<name>_controller.dart`**:
   ```dart
   import 'package:flutter_riverpod/flutter_riverpod.dart';
   import 'package:riverpod_annotation/riverpod_annotation.dart';

   part '<name>_controller.g.dart';

   @riverpod
   class <PascalName>Controller extends _$<PascalName>Controller {
     @override
     Future<void> build() async {
       // TODO: implement initial state
     }
   }
   ```

5. **Add route in `lib/core/router/app_router.dart`** if it exists:
   ```dart
   GoRoute(
     path: '/<name>',
     name: '<name>',
     builder: (_, __) => const <PascalName>View(),
   ),
   ```

6. **Generate widget test stub `test/presentation/<name>/<name>_view_test.dart`**:
   ```dart
   import 'package:flutter_test/flutter_test.dart';
   import 'package:flutter_riverpod/flutter_riverpod.dart';
   // TODO: import view

   void main() {
     testWidgets('<PascalName>View renders without error', (tester) async {
       // TODO: implement
     });
   }
   ```

7. **Run `dart run build_runner build`** to generate Riverpod provider files.

8. **Report**:
   - Files created (list)
   - Route added (path)
   - Next steps: implement state, design body widgets, add to navigation

## Constraints

- NEVER use `setState` — Riverpod only
- NEVER hardcode strings — use `easy_localization` keys
- NEVER hardcode colors — use `Theme.of(context).colorScheme`
- ALWAYS add `const` where possible (lint rule)
- ALWAYS create the `widgets/` subfolder, even empty
- If a screen with that name already exists, abort and ask for a different name
