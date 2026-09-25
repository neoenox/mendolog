import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import 'domain.dart';
import 'ads.dart';
import 'export.dart';
import 'mutation_controller.dart';
import 'storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(MobileAds.instance.initialize());
  final preferences = await SharedPreferences.getInstance();
  runApp(MendologApp(store: MendologStore(preferences)));
}

class MendologApp extends StatelessWidget {
  const MendologApp({super.key, required this.store});
  final MendologStore store;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'めんどログ',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff476b5c)),
      useMaterial3: true,
    ),
    home: MendologHome(store: store),
  );
}

class MendologHome extends StatefulWidget {
  const MendologHome({super.key, required this.store});
  final MendologStore store;

  @override
  State<MendologHome> createState() => _MendologHomeState();
}

class _MendologHomeState extends State<MendologHome> {
  late final MendologMutationController _mutations;
  MendologData get data => _mutations.data;

  @override
  void initState() {
    super.initState();
    // Load before the first build so recovery state can drive the UI.
    _mutations = MendologMutationController(
      MendologStorePersistence(widget.store),
    );
  }

  int tab = 0;
  final List<TextEditingController> _ephemeralControllers = [];

  TextEditingController _newEphemeralController() {
    final controller = TextEditingController();
    _ephemeralControllers.add(controller);
    return controller;
  }

  @override
  void dispose() {
    for (final controller in _ephemeralControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<bool> _runMutation(Future<bool> Function() mutation) async {
    try {
      final changed = await mutation();
      if (!mounted) return false;
      if (changed) setState(() {});
      return changed;
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
      return false;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存できませんでした。内容は変更されていません。もう一度お試しください。')),
        );
      }
      return false;
    }
  }

  Future<void> _record(FrictionCategory category, String target) async {
    await _runMutation(() => _mutations.record(category, target));
  }

  Future<void> _openRecorder(FrictionCategory category) async {
    final controller = _newEphemeralController();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom +
              MediaQuery.paddingOf(context).bottom +
              20,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            final targets = data.recentTargets;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${category.emoji} ${category.label}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (targets.isNotEmpty) ...[
                  const Text('最近使った対象'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: targets
                        .map(
                          (target) => ActionChip(
                            label: Text(target),
                            onPressed: () => Navigator.pop(context, target),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: controller,
                  autofocus: targets.isEmpty,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '対象を入力',
                    hintText: '例：爪切り',
                  ),
                  onSubmitted: (value) => Navigator.pop(context, value),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, controller.text),
                    child: const Text('記録する'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (selected != null) await _record(category, selected);
  }

  Future<void> _startImprovement(ImprovementSuggestion suggestion) async {
    final detailsController = _newEphemeralController();
    final details = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${suggestion.canonicalTarget}の改善'),
        content: TextField(
          controller: detailsController,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: '場所・手順（任意）',
            hintText: '例：洗面所の右側の引き出し',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, detailsController.text.trim()),
            child: const Text('改善を始める'),
          ),
        ],
      ),
    );
    if (!mounted || details == null) return;
    await _runMutation(() => _mutations.startImprovement(suggestion, details));
  }

  Future<void> _finishImprovement(
    Improvement improvement,
    ImprovementStatus status,
  ) async {
    await _runMutation(() => _mutations.finishImprovement(improvement, status));
  }

  Future<void> _exportData() async {
    await Share.share(encodeForExport(data), subject: 'めんどログのデータ');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('めんどログ'),
      centerTitle: false,
      actions: [
        IconButton(
          onPressed: _exportData,
          icon: const Icon(Icons.ios_share_outlined),
          tooltip: 'データを書き出す',
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          if (widget.store.recoveryRequired) _recoveryBanner(),
          Expanded(
            child: IndexedStack(
              index: tab,
              children: [_home(), _history(), _insights()],
            ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            label: '記録',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: '履歴'),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            label: '集計',
          ),
        ],
      ),
    ),
  );

  Widget _recoveryBanner() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.archive_outlined, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '前回のデータは読み取れなかったため端末内に退避しました。'
                '新しい記録から始めましょう。',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _home() {
    final suggestions = data.suggestions(DateTime.now());
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.paddingOf(context).bottom + 28,
      ),
      children: [
        Text('いま、何がめんどかった？', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          '記録→整理→次の行動。繰り返す面倒を記録すると、直近30日の集計と改善候補が見えてきます。まずは1件だけ残してみましょう。記録は端末内に保存されます。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        const Text('無料で使えるコア機能です。広告が表示できなくても、記録・閲覧・データ書き出しはそのまま使えます。'),
        const SizedBox(height: 8),
        const MonetizationBanner(),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.7,
          children: FrictionCategory.values
              .map(
                (category) => FilledButton.tonal(
                  key: Key('record-${category.name}-button'),
                  onPressed: () => _openRecorder(category),
                  child: Text('${category.emoji}  ${category.label}'),
                ),
              )
              .toList(),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('改善の候補', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...suggestions.map(
            (suggestion) => Card(
              child: ListTile(
                leading: const Icon(Icons.lightbulb_outline),
                title: Text(
                  '${suggestion.category.label}「${suggestion.canonicalTarget}」',
                ),
                subtitle: Text(
                  '直近30日で${suggestion.count}回。${suggestion.title}？',
                ),
                trailing: TextButton(
                  onPressed: () => _startImprovement(suggestion),
                  child: const Text('改善する'),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _history() => data.events.isEmpty
      ? const Center(child: Text('まだ記録がありません。記録すると、何が多いかを振り返れます。'))
      : ListView.builder(
          padding: EdgeInsets.fromLTRB(
            12,
            12,
            12,
            MediaQuery.paddingOf(context).bottom + 28,
          ),
          itemCount: data.events.length,
          itemBuilder: (context, index) {
            final event = data.events[data.events.length - 1 - index];
            return Dismissible(
              key: ValueKey(event.id),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) => _confirmDelete(event),
              background: Container(
                color: Theme.of(context).colorScheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
              child: ListTile(
                leading: Text(
                  event.category.emoji,
                  style: const TextStyle(fontSize: 24),
                ),
                title: Text(
                  '${event.category.label} · ${event.canonicalTarget}',
                ),
                subtitle: Text(_formatDate(event.occurredAt.toLocal())),
                // スワイプ削除はTalkBackから操作できないため、明示的な
                // 削除ボタン(意味ラベル付き)を並行して提供する。
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'この記録を削除',
                  onPressed: () => _confirmDelete(event),
                ),
              ),
            );
          },
        );

  Future<bool> _confirmDelete(FrictionEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('記録を削除しますか？'),
        content: Text('${event.category.label} · ${event.canonicalTarget}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    return _runMutation(() => _mutations.deleteEvent(event));
  }

  Widget _insights() {
    final now = DateTime.now();
    final rows = <Widget>[];
    for (final category in FrictionCategory.values) {
      final count = data.recentCount(category: category, now: now);
      if (count > 0) {
        rows.add(
          ListTile(
            leading: Text(category.emoji, style: const TextStyle(fontSize: 22)),
            title: Text(category.label),
            trailing: Text('$count回'),
          ),
        );
      }
    }
    final improvements = data.improvements;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.paddingOf(context).bottom + 28,
      ),
      children: [
        Text('直近30日の集計', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        if (rows.isEmpty) const Text('記録が増えると、ここに集計が表示されます。') else ...rows,
        if (improvements.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('改善の効果', style: Theme.of(context).textTheme.titleLarge),
          ...improvements.map((item) {
            final comparison = data.comparison(item, now);
            return ListTile(
              title: Text('${item.canonicalTarget} · ${item.title}'),
              subtitle: Text(
                '${item.details.isEmpty ? '詳細未設定' : item.details}\n'
                '${item.isActive ? (comparison.isComplete ? '改善前 ${comparison.before}回 → 改善後 ${comparison.after}回' : '観測中（${comparison.observedAfterDays}/30日）: 改善前 ${comparison.before}回 → 現在 ${comparison.after}回') : '${item.status == ImprovementStatus.completed ? '完了' : '中止'}: 改善前 ${comparison.before}回 → 改善後 ${comparison.after}回'}',
              ),
              trailing: item.isActive
                  ? PopupMenuButton<ImprovementStatus>(
                      tooltip: '改善の状態を更新',
                      onSelected: (status) => _finishImprovement(item, status),
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: ImprovementStatus.completed,
                          child: Text('改善できた'),
                        ),
                        PopupMenuItem(
                          value: ImprovementStatus.abandoned,
                          child: Text('効果なし・中止'),
                        ),
                      ],
                    )
                  : Text(
                      item.status == ImprovementStatus.completed ? '完了' : '中止',
                    ),
            );
          }),
        ],
      ],
    );
  }

  String _formatDate(DateTime date) =>
      '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
