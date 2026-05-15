import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/device_record.dart';
import '../scanner_state.dart';
import '../services/device_memory.dart';
import 'device_detail_page.dart';

enum _Step { intro, phase, result }

const int _maxFarPhases = 3;

/// We use only the last [_destinationWindow] of each phase as the
/// "at-position" reading — so if the user walks the first half of the phase
/// and stands the second half, the reading reflects the destination.
const Duration _destinationWindow = Duration(seconds: 3);

/// User can't end a phase faster than this — guards against accidental taps
/// and ensures at least a few samples land in the destination window.
const Duration _minPhaseDuration = Duration(seconds: 2);

const List<({String icon, String title, String body})> _phaseCopy = [
  (
    icon: '📍',
    title: 'Step next to the mystery device',
    body: 'Put the phone within ~5 cm of the device. Hold there for a moment, '
        'then tap Continue.',
  ),
  (
    icon: '🚶',
    title: 'Walk 3+ m away — direction 1',
    body: 'Walk away from the device. The further the better. Stop, then tap '
        '"I\'m here."',
  ),
  (
    icon: '🧭',
    title: 'Walk 3+ m away — direction 2',
    body: 'Return near, then walk away in a *different* direction. Devices '
        'truly close to you drop signal whichever way you walk; a stronger '
        'signal lurking behind only drops in some directions, not all.',
  ),
  (
    icon: '🧭',
    title: 'Walk 3+ m away — direction 3',
    body: 'Yet another direction. Same idea — walk, stop, tap.',
  ),
];

class IdentifyDevicePage extends StatefulWidget {
  const IdentifyDevicePage({super.key});

  @override
  State<IdentifyDevicePage> createState() => _IdentifyDevicePageState();
}

class _IdentifyDevicePageState extends State<IdentifyDevicePage> {
  _Step _step = _Step.intro;
  int _phaseIndex = 0;
  int _targetPhaseCount = 3;

  final List<DateTime> _phaseStarts = [];
  final List<DateTime> _phaseEnds = [];

  @override
  void initState() {
    super.initState();
    ScannerState.instance.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ScannerState.instance.removeListener(_onChange);
    super.dispose();
  }

  void _start() {
    if (!ScannerState.instance.isScanning) {
      ScannerState.instance.startScan();
    }
    setState(() {
      _step = _Step.phase;
      _phaseIndex = 0;
      _targetPhaseCount = 3;
      _phaseStarts
        ..clear()
        ..add(DateTime.now());
      _phaseEnds.clear();
    });
  }

  void _continueToNextPhase() {
    if (!_canFinishPhase) return;
    _phaseEnds.add(DateTime.now());
    setState(() {
      _phaseIndex++;
      _phaseStarts.add(DateTime.now());
    });
  }

  void _addOneMore() {
    if (!_canFinishPhase) return;
    _phaseEnds.add(DateTime.now());
    setState(() {
      _targetPhaseCount = math.min(_targetPhaseCount + 1, 1 + _maxFarPhases);
      _phaseIndex++;
      _phaseStarts.add(DateTime.now());
    });
  }

  void _showResults() {
    if (!_canFinishPhase) return;
    _phaseEnds.add(DateTime.now());
    setState(() => _step = _Step.result);
  }

  void _restart() {
    setState(() {
      _step = _Step.intro;
      _phaseIndex = 0;
      _targetPhaseCount = 3;
      _phaseStarts.clear();
      _phaseEnds.clear();
    });
  }

  bool get _canFinishPhase {
    if (_phaseStarts.length <= _phaseIndex) return false;
    return DateTime.now().difference(_phaseStarts.last) >= _minPhaseDuration;
  }

  Duration get _currentPhaseDuration {
    if (_phaseStarts.length <= _phaseIndex) return Duration.zero;
    return DateTime.now().difference(_phaseStarts.last);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('What is this device?')),
      body: SafeArea(
        minimum: const EdgeInsets.only(bottom: 12),
        child: switch (_step) {
          _Step.intro => _IntroBody(onStart: _start),
          _Step.phase => _PhaseBody(
              phaseIndex: _phaseIndex,
              totalPhases: _targetPhaseCount,
              phaseDuration: _currentPhaseDuration,
              canFinish: _canFinishPhase,
              canAddOneMore: _phaseIndex == _targetPhaseCount - 1 &&
                  _targetPhaseCount < 1 + _maxFarPhases,
              isLastPhase: _phaseIndex == _targetPhaseCount - 1,
              onContinue: _continueToNextPhase,
              onShowResults: _showResults,
              onAddOneMore: _addOneMore,
            ),
          _Step.result => _ResultBody(
              results: _computeResults(),
              farDirectionsUsed: _phaseStarts.length - 1,
              onRestart: _restart,
            ),
        },
      ),
    );
  }

  List<_Score> _computeResults() {
    if (_phaseStarts.length != _phaseEnds.length) return const [];
    if (_phaseStarts.length < 3) return const [];

    final all = ScannerState.instance.allDevices.values.toList();
    final out = <_Score>[];
    for (final d in all) {
      double destinationAvg(int phase) {
        final phaseStart = _phaseStarts[phase];
        final phaseEnd = _phaseEnds[phase];
        final windowStart = phaseEnd.subtract(_destinationWindow);
        final readStart =
            windowStart.isAfter(phaseStart) ? windowStart : phaseStart;
        final relevant = d.samples
            .where((s) => !s.time.isBefore(readStart) && !s.time.isAfter(phaseEnd))
            .toList();
        if (relevant.isEmpty) return double.nan;
        final sum = relevant.map((s) => s.rssi).reduce((a, b) => a + b);
        return sum / relevant.length;
      }

      final closeAvg = destinationAvg(0);
      final farAvgs = <double>[];
      for (var i = 1; i < _phaseStarts.length; i++) {
        final a = destinationAvg(i);
        if (!a.isNaN) farAvgs.add(a);
      }
      if (closeAvg.isNaN || farAvgs.length < 2) continue;

      final worstFar = farAvgs.reduce(math.max);
      final score = closeAvg - worstFar;
      out.add(_Score(d, score, closeAvg, farAvgs, worstFar));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }
}

class _Score {
  _Score(this.device, this.score, this.close, this.farAvgs, this.worstFar);
  final DeviceRecord device;
  final double score;
  final double close;
  final List<double> farAvgs;
  final double worstFar;

  String get confidenceLabel {
    if (score >= 20) return 'Strong match';
    if (score >= 10) return 'Likely match';
    if (score >= 5) return 'Possible match';
    return 'Weak / unrelated';
  }

  Color confidenceColor() {
    if (score >= 20) return const Color(0xFF2E7D32);
    if (score >= 10) return const Color(0xFF66BB6A);
    if (score >= 5) return const Color(0xFFFFA726);
    return Colors.grey;
  }
}

class _IntroBody extends StatelessWidget {
  const _IntroBody({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.center_focus_strong,
            size: 72,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Identify a device by triangulation',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'You\'ll do one close capture and 2–3 far captures from different '
            'directions, walking between each. A device truly in front of you '
            'will drop signal in every direction; a stronger device behind a '
            'wall only drops in some.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          FilledButton(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Start identifying'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _PhaseBody extends StatelessWidget {
  const _PhaseBody({
    required this.phaseIndex,
    required this.totalPhases,
    required this.phaseDuration,
    required this.canFinish,
    required this.canAddOneMore,
    required this.isLastPhase,
    required this.onContinue,
    required this.onShowResults,
    required this.onAddOneMore,
  });

  final int phaseIndex;
  final int totalPhases;
  final Duration phaseDuration;
  final bool canFinish;
  final bool canAddOneMore;
  final bool isLastPhase;
  final VoidCallback onContinue;
  final VoidCallback onShowResults;
  final VoidCallback onAddOneMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copy = _phaseCopy[phaseIndex];
    final buttonLabel = isLastPhase ? "I'm here — show results" : "I'm here";

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepIndicator(current: phaseIndex, total: totalPhases),
          const SizedBox(height: 20),
          Center(child: Text(copy.icon, style: const TextStyle(fontSize: 56))),
          const SizedBox(height: 12),
          Text(
            copy.title,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            copy.body,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _LiveFeedback(phaseDuration: phaseDuration),
          const Spacer(),
          if (isLastPhase) ...[
            FilledButton(
              onPressed: canFinish ? onShowResults : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(canFinish
                  ? buttonLabel
                  : "Hold steady (${(_minPhaseDuration.inSeconds - phaseDuration.inSeconds).clamp(0, 99)}s)"),
            ),
            if (canAddOneMore) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: canFinish ? onAddOneMore : null,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Add one more direction'),
              ),
            ],
          ] else
            FilledButton(
              onPressed: canFinish ? onContinue : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(canFinish
                  ? buttonLabel
                  : "Hold steady (${(_minPhaseDuration.inSeconds - phaseDuration.inSeconds).clamp(0, 99)}s)"),
            ),
        ],
      ),
    );
  }
}

class _LiveFeedback extends StatelessWidget {
  const _LiveFeedback({required this.phaseDuration});
  final Duration phaseDuration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = ScannerState.instance.allDevices.values.toList()
      ..sort((a, b) => b.currentRssi.compareTo(a.currentRssi));
    final top = devices.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.podcasts,
                  size: 16, color: theme.colorScheme.outline),
              const SizedBox(width: 6),
              Text(
                'Live · strongest nearby (${phaseDuration.inSeconds}s)',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (top.isEmpty)
            Text(
              'Listening for devices…',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            )
          else
            ...top.map((d) {
              final hasName =
                  d.localName != null && d.localName!.isNotEmpty;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        hasName ? d.name : '(unnamed) · ${d.id.str.substring(d.id.str.length - 5)}',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      '${d.currentRssi} dBm',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _ResultBody extends StatelessWidget {
  const _ResultBody({
    required this.results,
    required this.farDirectionsUsed,
    required this.onRestart,
  });
  final List<_Score> results;
  final int farDirectionsUsed;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qualifying =
        results.where((r) => r.score >= 5).toList(growable: false);

    if (qualifying.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.question_mark,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('No clear match found', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'No device dropped enough signal across $farDirectionsUsed '
              'different far directions. Try again with bigger distances or '
              'more obviously different directions.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            FilledButton(
              onPressed: onRestart,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Compared across $farDirectionsUsed far directions',
            style: theme.textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Best match',
            style: theme.textTheme.titleMedium,
          ),
        ),
        _ResultCard(score: qualifying.first, highlighted: true),
        if (qualifying.length > 1) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Other candidates',
              style: theme.textTheme.titleMedium,
            ),
          ),
          ...qualifying
              .skip(1)
              .take(4)
              .map((s) => _ResultCard(score: s, highlighted: false)),
        ],
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onRestart,
                  child: const Text('Run again'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.score, required this.highlighted});
  final _Score score;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mem = DeviceMemory.instance;
    final label = mem.labelFor(score.device.id.str);
    final name = label ?? score.device.name;
    final farStrs = score.farAvgs.map((v) => v.round().toString()).join(', ');

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      color: highlighted ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: score.confidenceColor(),
          child: Text(
            '${score.score.round()}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Text(name, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              score.confidenceLabel,
              style: TextStyle(color: score.confidenceColor()),
            ),
            Text(
              'near ${score.close.round()} dBm · far [$farStrs] '
              '· worst far ${score.worstFar.round()}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DeviceDetailPage(deviceId: score.device.id),
          ),
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.current,
    required this.total,
  });
  final int current;
  final int total;
  static const bool completed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: List.generate(total, (i) {
        final isCurrent = i == current;
        final isDone = i < current || (i == current && completed);
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 6,
            decoration: BoxDecoration(
              color: isDone
                  ? theme.colorScheme.primary
                  : isCurrent
                      ? theme.colorScheme.primary.withValues(alpha: 0.5)
                      : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }
}
