import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../translations.dart';
import '../ui/app_theme.dart';

class TokenUsageScreen extends StatefulWidget {
  const TokenUsageScreen({super.key});

  @override
  State<TokenUsageScreen> createState() => _TokenUsageScreenState();
}

class _TokenUsageScreenState extends State<TokenUsageScreen> {
  String timeFilter = 'all';
  String groupBy = 'model';
  String chartType = 'bar';
  String selectedModel = 'all';
  String selectedEndpoint = 'all';
  String selectedSession = 'all';
  DateTimeRange? customDateRange;

  static const colors = [
    Color(0xffffffff),
    Color(0xffcccccc),
    Color(0xff999999),
    Color(0xffe0e0e0),
    Color(0xffb0b0b0),
    Color(0xff777777),
    Color(0xffd4d4d4),
    Color(0xff888888),
    Color(0xffaaaaaa),
    Color(0xff666666),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final copy = UiCopy(app.language);
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final filtered = _filtered(app.tokenUsageData);
    final grouped = _grouped(filtered);
    final totals = _totals(filtered);
    final models = app.tokenUsageData.map((item) => item.model).toSet().toList()
      ..sort();
    final endpoints =
        app.tokenUsageData.map((item) => item.endpoint).toSet().toList()
          ..sort();
    
    final sessionsMap = {
      for (final s in app.sessions) s.id: s.title,
    };
    final sessionIds = app.tokenUsageData
        .map((item) => item.sessionId)
        .whereType<String>()
        .toSet()
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: p.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.primary.withValues(alpha: 0.20)),
              ),
              child: Icon(LucideIcons.trendingUp, color: p.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TELEMETRY',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.cyan.shade400,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
                Text(
                  '${copy.t('tokenUsage', 'title')}.',
                  style: TextStyle(
                    fontSize: 30,
                    color: p.primary,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        GlassPanel(
          radius: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _ChoiceGroup(
                    value: timeFilter,
                    values: {
                      'hour': 'Last 1H',
                      'today': copy.t('tokenUsage', 'today'),
                      'week': copy.t('tokenUsage', 'thisWeek'),
                      'month': copy.t('tokenUsage', 'thisMonth'),
                      'custom': customDateRange != null
                          ? '${DateFormat.Md().format(customDateRange!.start)} - ${DateFormat.Md().format(customDateRange!.end)}'
                          : 'Custom Date',
                      'all': copy.t('tokenUsage', 'allTime'),
                    },
                    onChanged: (value) async {
                      if (value == 'custom') {
                        final range = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 1)),
                        );
                        if (range != null) {
                          setState(() {
                            timeFilter = value;
                            customDateRange = range;
                          });
                        }
                      } else {
                        setState(() => timeFilter = value);
                      }
                    },
                  ),
                  _Dropdown(
                    value: selectedModel,
                    values: ['all', ...models],
                    labels: {'all': copy.t('tokenUsage', 'allModels')},
                    onChanged: (value) => setState(() => selectedModel = value),
                  ),
                  _Dropdown(
                    value: selectedEndpoint,
                    values: ['all', ...endpoints],
                    labels: {'all': copy.t('tokenUsage', 'allEndpoints')},
                    onChanged: (value) =>
                        setState(() => selectedEndpoint = value),
                  ),
                  _Dropdown(
                    value: selectedSession,
                    values: ['all', ...sessionIds],
                    labels: {
                      'all': 'All Sessions',
                      for (final id in sessionIds)
                        id: sessionsMap[id] ?? 'Unknown Session',
                    },
                    onChanged: (value) =>
                        setState(() => selectedSession = value),
                  ),
                  _ChoiceGroup(
                    value: groupBy,
                    values: {
                      'model': copy.t('tokenUsage', 'byModel'),
                      'endpoint': copy.t('tokenUsage', 'byEndpoint'),
                    },
                    onChanged: (value) => setState(() => groupBy = value),
                  ),
                  _IconChoice(
                    value: chartType,
                    onChanged: (value) => setState(() => chartType = value),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 620;
            final cards = [
              _StatCard(
                label: copy.t('tokenUsage', 'totalTokens'),
                value: totals.total,
                color: p.primary,
              ),
              _StatCard(
                label: copy.t('tokenUsage', 'inputTokens'),
                value: totals.input,
                color: p.onSurface.withValues(alpha: 0.70),
              ),
              _StatCard(
                label: copy.t('tokenUsage', 'outputTokens'),
                value: totals.output,
                color: p.secondary,
              ),
              if (totals.cachedInput > 0)
                _StatCard(
                  label: 'Cache Hits',
                  value: totals.cachedInput,
                  color: const Color(0xff22c55e),
                ),
              if (totals.cacheCreation > 0)
                _StatCard(
                  label: 'Cache Writes',
                  value: totals.cacheCreation,
                  color: const Color(0xfff59e0b),
                ),
            ];
            return wide
                ? Row(
                    children: [
                      for (var i = 0; i < cards.length; i++) ...[
                        Expanded(child: cards[i]),
                        if (i != cards.length - 1) const SizedBox(width: 12),
                      ],
                    ],
                  )
                : Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: cards
                        .map(
                          (card) => SizedBox(
                            width: (constraints.maxWidth - 16) / 2,
                            child: card,
                          ),
                        )
                        .toList(),
                  );
          },
        ),
        const SizedBox(height: 18),
        Text(
          chartType == 'line'
              ? copy.t('tokenUsage', 'overTime')
              : '${copy.t('tokenUsage', 'byModel')} / ${copy.t('tokenUsage', 'byEndpoint')}',
          style: _labelStyle(context),
        ),
        const SizedBox(height: 8),
        GlassPanel(
          radius: 24,
          child: SizedBox(
            height: 320,
            child: grouped.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.trendingUp,
                          size: 48,
                          color: p.primary.withValues(alpha: 0.25),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          copy.t('tokenUsage', 'noData'),
                          style: TextStyle(
                            color: p.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  )
                : _chart(grouped, filtered, p),
          ),
        ),
        const SizedBox(height: 24),
        _ModelUsageBreakdown(records: filtered),
        const SizedBox(height: 24),
        _CustomCounters(
          filteredAll: app.tokenUsageData,
          selectedModel: selectedModel,
          selectedEndpoint: selectedEndpoint,
          colors: colors,
        ),
        const SizedBox(height: 24),
        GlassPanel(
          radius: 22,
          borderColor: p.error.withValues(alpha: 0.22),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DANGER ZONE',
                      style: TextStyle(
                        color: p.error,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.8,
                      ),
                    ),
                    Text(
                      'Permanently wipe token usage analytics records.',
                      style: TextStyle(color: p.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(copy.t('tokenUsage', 'resetConfirm')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Yes, Reset'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) app.resetTokenUsage();
                },
                icon: Icon(LucideIcons.rotateCw, color: p.error, size: 16),
                label: Text('${copy.t('tokenUsage', 'reset')} All Data'),
                style: OutlinedButton.styleFrom(foregroundColor: p.error),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<TokenUsageRecord> _filtered(List<TokenUsageRecord> data) {
    final now = DateTime.now().millisecondsSinceEpoch;
    const hour = 60 * 60 * 1000;
    const day = 24 * 60 * 60 * 1000;
    
    final start = switch (timeFilter) {
      'hour' => now - hour,
      'today' => now - day,
      'week' => now - 7 * day,
      'month' => now - 30 * day,
      'custom' => customDateRange?.start.millisecondsSinceEpoch ?? 0,
      _ => 0,
    };
    
    final end = switch (timeFilter) {
      'custom' => customDateRange?.end.add(const Duration(days: 1)).millisecondsSinceEpoch ?? now,
      _ => now,
    };

    return data.where((item) {
      return item.timestamp >= start &&
          item.timestamp <= end &&
          (selectedModel == 'all' || item.model == selectedModel) &&
          (selectedEndpoint == 'all' || item.endpoint == selectedEndpoint) &&
          (selectedSession == 'all' || item.sessionId == selectedSession);
    }).toList();
  }

  List<_Group> _grouped(List<TokenUsageRecord> data) {
    final groups = <String, _Totals>{};
    for (final item in data) {
      final key = groupBy == 'model' ? item.model : item.endpoint;
      final totals = groups.putIfAbsent(key, () => _Totals());
      totals.input += item.inputTokens;
      totals.output += item.outputTokens;
      totals.total += item.totalTokens;
    }
    final result = groups.entries
        .map(
          (entry) => _Group(
            entry.key,
            entry.value.input,
            entry.value.output,
            entry.value.total,
          ),
        )
        .toList();
    result.sort((a, b) => b.total.compareTo(a.total));
    return result;
  }

  _Totals _totals(List<TokenUsageRecord> data) {
    final totals = _Totals();
    for (final item in data) {
      totals.input += item.inputTokens;
      totals.output += item.outputTokens;
      totals.total += item.totalTokens;
      totals.cachedInput += item.cachedInputTokens;
      totals.cacheCreation += item.cacheCreationInputTokens;
    }
    return totals;
  }

  Widget _chart(
    List<_Group> grouped,
    List<TokenUsageRecord> filtered,
    AppPalette p,
  ) {
    if (chartType == 'pie') {
      final sum = grouped.fold<int>(0, (total, item) => total + item.total);
      return PieChart(
        PieChartData(
          sections: grouped.take(10).toList().asMap().entries.map((entry) {
            final item = entry.value;
            final percent = sum == 0 ? 0 : item.total / sum * 100;
            return PieChartSectionData(
              color: colors[entry.key % colors.length],
              value: item.total.toDouble(),
              title: '${item.name}\n${percent.toStringAsFixed(0)}%',
              radius: 88,
              titleStyle: TextStyle(
                color: entry.key == 0 ? Colors.black : Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 10,
              ),
            );
          }).toList(),
          sectionsSpace: 2,
          centerSpaceRadius: 42,
        ),
      );
    }
    if (chartType == 'line') {
      final byDay = <String, int>{};
      for (final item in filtered) {
        final label = DateFormat.Md().format(
          DateTime.fromMillisecondsSinceEpoch(item.timestamp),
        );
        byDay[label] = (byDay[label] ?? 0) + item.totalTokens;
      }
      final entries = byDay.entries.toList().take(30).toList();
      return LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: p.outline, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 44),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < entries.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        entries[index].key,
                        style: TextStyle(color: p.onSurfaceVariant, fontSize: 10),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
                reservedSize: 30,
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: entries
                  .asMap()
                  .entries
                  .map(
                    (entry) => FlSpot(
                      entry.key.toDouble(),
                      entry.value.value.toDouble(),
                    ),
                  )
                  .toList(),
              color: p.primary,
              barWidth: 3,
              isCurved: true,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      );
    }
    return BarChart(
      BarChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: p.outline, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 44),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                final items = grouped.take(10).toList();
                if (index >= 0 && index < items.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      width: 50,
                      child: Text(
                        items[index].name,
                        style: TextStyle(color: p.onSurfaceVariant, fontSize: 10),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
              reservedSize: 30,
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barGroups: grouped.take(10).toList().asMap().entries.map((entry) {
          final item = entry.value;
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: item.input.toDouble(),
                color: colors[0],
                width: 9,
                borderRadius: BorderRadius.circular(4),
              ),
              BarChartRodData(
                toY: item.output.toDouble(),
                color: colors[2],
                width: 9,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: _labelStyle(context)),
          const SizedBox(height: 10),
          Text(
            NumberFormat.decimalPattern().format(value),
            style: TextStyle(
              color: color,
              fontSize: 30,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceGroup extends StatelessWidget {
  const _ChoiceGroup({
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String value;
  final Map<String, String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      children: values.entries
          .map(
            (entry) => ChoiceChip(
              selected: value == entry.key,
              label: Text(entry.value),
              onSelected: (_) => onChanged(entry.key),
            ),
          )
          .toList(),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      children:
          const {
                'bar': LucideIcons.barChart3,
                'line': LucideIcons.lineChart,
                'pie': LucideIcons.pieChart,
              }.entries
              .map(
                (entry) => ChoiceChip(
                  selected: value == entry.key,
                  avatar: Icon(entry.value, size: 14),
                  label: Text(entry.key),
                  onSelected: (_) => onChanged(entry.key),
                ),
              )
              .toList(),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.values,
    required this.labels,
    required this.onChanged,
  });

  final String value;
  final List<String> values;
  final Map<String, String> labels;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final unique = values.toSet().toList();
    return SizedBox(
      width: 170,
      child: DropdownButtonFormField<String>(
        initialValue: unique.contains(value) ? value : unique.first,
        items: unique
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Text(
                  labels[item] ?? item,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _ModelUsageBreakdown extends StatelessWidget {
  const _ModelUsageBreakdown({required this.records});

  final List<TokenUsageRecord> records;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final stats = _endpointModelStats(records);
    return GlassPanel(
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.bot, color: p.primary, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'MODEL TOKEN BREAKDOWN',
                  style: TextStyle(
                    color: p.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (stats.isEmpty)
            Text('No model usage in this filter.', style: _mutedStyle(p))
          else
            ...stats.map(
              (epStat) => Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      epStat.endpoint.toUpperCase(),
                      style: TextStyle(
                        color: p.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...epStat.models.map((item) => _ModelUsageRow(stat: item)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModelUsageRow extends StatelessWidget {
  const _ModelUsageRow({required this.stat, this.compact = false});

  final _ModelUsageStat stat;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 5 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stat.model,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.onSurface,
              fontSize: compact ? 11 : 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: compact ? 3 : 6),
          Wrap(
            spacing: compact ? 8 : 16,
            runSpacing: 4,
            children: [
              _UsageMetric(label: 'Input', value: stat.input),
              _UsageMetric(label: 'Output', value: stat.output),
              _UsageMetric(label: 'Total', value: stat.total, strong: true),
              _UsageMetric(label: 'Count', value: stat.count),
              if (stat.cachedInput > 0)
                _UsageMetric(label: 'Cache Hit', value: stat.cachedInput),
              if (stat.cacheCreation > 0)
                _UsageMetric(label: 'Cache Write', value: stat.cacheCreation),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsageMetric extends StatelessWidget {
  const _UsageMetric({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final int value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Text(
      '$label ${NumberFormat.compact().format(value)}',
      style: TextStyle(
        color: strong ? p.primary : p.onSurfaceVariant,
        fontSize: 11,
        fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
      ),
    );
  }
}

class _CustomCounters extends StatelessWidget {
  const _CustomCounters({
    required this.filteredAll,
    required this.selectedModel,
    required this.selectedEndpoint,
    required this.colors,
  });

  final List<TokenUsageRecord> filteredAll;
  final String selectedModel;
  final String selectedEndpoint;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final copy = UiCopy(app.language);
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(LucideIcons.plus, color: p.primary, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                copy.t('tokenUsage', 'customCounters').toUpperCase(),
                style: TextStyle(
                  color: p.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                ),
              ),
            ),
            Flexible(
              flex: 0,
              child: FilledButton(
                onPressed: () => _createCounter(context, app, copy),
                child: Text(
                  copy.t('tokenUsage', 'createCounter'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (app.customCounters.isEmpty)
          GlassPanel(
            radius: 24,
            child: Center(
              child: Text(
                copy.t('tokenUsage', 'noData'),
                style: TextStyle(color: p.onSurfaceVariant),
              ),
            ),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: app.customCounters.map((counter) {
              final stats = _counterStats(counter);
              final modelStats = _counterModelStats(counter);
              return SizedBox(
                width: 270,
                child: GlassPanel(
                  radius: 22,
                  borderColor: _color(counter.color),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              counter.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.edit2, size: 15),
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                _renameCounter(context, app, counter),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.rotateCw, size: 15),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _resetCounter(app, counter),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.trash2, size: 15),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _deleteCounter(app, counter),
                          ),
                        ],
                      ),
                      Text(
                        NumberFormat.decimalPattern().format(stats.total),
                        style: TextStyle(
                          color: _color(counter.color),
                          fontSize: 26,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      Text(
                        '${stats.count} requests',
                        style: TextStyle(
                          color: p.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        '${copy.t('tokenUsage', 'activeSince')}: ${DateFormat.yMd().format(DateTime.fromMillisecondsSinceEpoch(counter.createdAt))}',
                        style: TextStyle(
                          color: p.onSurfaceVariant.withValues(alpha: 0.7),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniStat(
                              label: 'Input',
                              value: stats.input,
                              color: p.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _MiniStat(
                              label: 'Output',
                              value: stats.output,
                              color: p.secondary,
                            ),
                          ),
                        ],
                      ),
                      if (stats.cachedInput > 0 || stats.cacheCreation > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (stats.cachedInput > 0)
                              Expanded(
                                child: _MiniStat(
                                  label: 'Cache Hit',
                                  value: stats.cachedInput,
                                  color: const Color(0xff22c55e),
                                ),
                              ),
                            if (stats.cachedInput > 0 &&
                                stats.cacheCreation > 0)
                              const SizedBox(width: 8),
                            if (stats.cacheCreation > 0)
                              Expanded(
                                child: _MiniStat(
                                  label: 'Cache Write',
                                  value: stats.cacheCreation,
                                  color: const Color(0xfff59e0b),
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (modelStats.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('MODELS BY ENDPOINT', style: _labelStyle(context)),
                        const SizedBox(height: 4),
                        ...modelStats.map(
                          (epStat) => Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  epStat.endpoint,
                                  style: TextStyle(
                                    color: _color(counter.color),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                ...epStat.models.map(
                                  (stat) =>
                                      _ModelUsageRow(stat: stat, compact: true),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  _CounterStats _counterStats(CustomCounter counter) {
    final data = filteredAll.where(
      (item) =>
          item.timestamp >= counter.createdAt &&
          (selectedModel == 'all' || item.model == selectedModel) &&
          (selectedEndpoint == 'all' || item.endpoint == selectedEndpoint),
    );
    final stats = _CounterStats();
    for (final item in data) {
      stats.total += item.totalTokens;
      stats.input += item.inputTokens;
      stats.output += item.outputTokens;
      stats.cachedInput += item.cachedInputTokens;
      stats.cacheCreation += item.cacheCreationInputTokens;
      stats.count += 1;
    }
    return stats;
  }

  List<_EndpointUsageStat> _counterModelStats(CustomCounter counter) {
    return _endpointModelStats(
      filteredAll.where(
        (item) =>
            item.timestamp >= counter.createdAt &&
            (selectedModel == 'all' || item.model == selectedModel) &&
            (selectedEndpoint == 'all' || item.endpoint == selectedEndpoint),
      ),
    );
  }

  Color _color(String value) {
    try {
      return Color(int.parse(value.replaceFirst('#', 'ff'), radix: 16));
    } catch (_) {
      return Colors.white;
    }
  }

  Future<void> _createCounter(
    BuildContext context,
    AdoetzAppState app,
    UiCopy copy,
  ) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy.t('tokenUsage', 'createCounter')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: copy.t('tokenUsage', 'counterName'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name?.trim().isNotEmpty == true) {
      final next = CustomCounter(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name!.trim(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
        color:
            '#${colors[app.customCounters.length % colors.length].toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
      );
      app.updateCustomCounters([...app.customCounters, next]);
    }
  }

  Future<void> _renameCounter(
    BuildContext context,
    AdoetzAppState app,
    CustomCounter counter,
  ) async {
    final controller = TextEditingController(text: counter.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name?.trim().isNotEmpty == true) {
      app.updateCustomCounters(
        app.customCounters
            .map(
              (item) => item.id == counter.id
                  ? item.copyWith(name: name!.trim())
                  : item,
            )
            .toList(),
      );
    }
  }

  void _resetCounter(AdoetzAppState app, CustomCounter counter) {
    app.updateCustomCounters(
      app.customCounters
          .map(
            (item) => item.id == counter.id
                ? item.copyWith(
                    createdAt: DateTime.now().millisecondsSinceEpoch,
                  )
                : item,
          )
          .toList(),
    );
  }

  void _deleteCounter(AdoetzAppState app, CustomCounter counter) {
    app.updateCustomCounters(
      app.customCounters.where((item) => item.id != counter.id).toList(),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.surfaceDim,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.outline),
      ),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: p.onSurfaceVariant,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            NumberFormat.compact().format(value),
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _Totals {
  int input = 0;
  int output = 0;
  int total = 0;
  int cachedInput = 0;
  int cacheCreation = 0;
}

class _Group {
  _Group(this.name, this.input, this.output, this.total);

  final String name;
  final int input;
  final int output;
  final int total;
}

class _CounterStats {
  int total = 0;
  int input = 0;
  int output = 0;
  int cachedInput = 0;
  int cacheCreation = 0;
  int count = 0;
}

class _EndpointUsageStat {
  _EndpointUsageStat(this.endpoint);
  final String endpoint;
  int total = 0;
  final List<_ModelUsageStat> models = [];
}

class _ModelUsageStat {
  _ModelUsageStat(this.model);

  final String model;
  int input = 0;
  int output = 0;
  int total = 0;
  int cachedInput = 0;
  int cacheCreation = 0;
  int count = 0;
}

List<_EndpointUsageStat> _endpointModelStats(
  Iterable<TokenUsageRecord> records,
) {
  final endpointMap = <String, _EndpointUsageStat>{};

  for (final record in records) {
    final epKey = record.endpoint.trim().isEmpty
        ? 'Unknown endpoint'
        : record.endpoint;
    final modelKey = record.model.trim().isEmpty
        ? 'Unknown model'
        : record.model;

    final epStat = endpointMap.putIfAbsent(
      epKey,
      () => _EndpointUsageStat(epKey),
    );
    epStat.total += record.totalTokens;

    var modelStat = epStat.models.firstWhere(
      (m) => m.model == modelKey,
      orElse: () {
        final newModel = _ModelUsageStat(modelKey);
        epStat.models.add(newModel);
        return newModel;
      },
    );

    modelStat.input += record.inputTokens;
    modelStat.output += record.outputTokens;
    modelStat.total += record.totalTokens;
    modelStat.cachedInput += record.cachedInputTokens;
    modelStat.cacheCreation += record.cacheCreationInputTokens;
    modelStat.count += 1;
  }

  final result = endpointMap.values.toList()
    ..sort((a, b) => b.total.compareTo(a.total));

  for (final ep in result) {
    ep.models.sort((a, b) => b.total.compareTo(a.total));
  }
  return result;
}

TextStyle _mutedStyle(AppPalette p) {
  return TextStyle(
    color: p.onSurfaceVariant,
    fontSize: 11,
    fontWeight: FontWeight.w700,
  );
}

TextStyle _labelStyle(BuildContext context) {
  final p = AppPalette.fromBrightness(
    Theme.of(context).brightness == Brightness.dark,
  );
  return TextStyle(
    fontSize: 10,
    color: p.onSurfaceVariant,
    fontWeight: FontWeight.w900,
    letterSpacing: 1.4,
  );
}
