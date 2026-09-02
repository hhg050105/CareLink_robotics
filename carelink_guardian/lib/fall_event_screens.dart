import 'package:flutter/material.dart';

import 'fall_event.dart';

class FallEventListScreen extends StatelessWidget {
  const FallEventListScreen({super.key, this._repository});

  final FallEventRepository? _repository;

  @override
  Widget build(BuildContext context) {
    final repository = _repository ?? FallEventRepository();
    return Scaffold(
      appBar: AppBar(title: const Text('최근 낙상 이력')),
      body: StreamBuilder<List<FallEvent>>(
        stream: repository.watchRecent(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const _ErrorView();
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final events = snapshot.data!;
          if (events.isEmpty) {
            return const Center(child: Text('낙상 감지 이력이 없습니다.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final event = events[index];
              return Card(
                child: ListTile(
                  leading: Icon(
                    event.acknowledged
                        ? Icons.check_circle_rounded
                        : Icons.warning_rounded,
                    color: event.acknowledged ? Colors.green : Colors.red,
                  ),
                  title: Text('${event.cameraId} 카메라'),
                  subtitle: Text(_formatDateTime(event.detectedAt)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FallEventDetailScreen(eventId: event.id),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class FallEventDetailScreen extends StatefulWidget {
  const FallEventDetailScreen({
    super.key,
    required this.eventId,
    this._repository,
  });

  final String eventId;
  final FallEventRepository? _repository;

  @override
  State<FallEventDetailScreen> createState() => _FallEventDetailScreenState();
}

class _FallEventDetailScreenState extends State<FallEventDetailScreen> {
  late final FallEventRepository _repository;
  late Future<FallEvent?> _event;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _repository = widget._repository ?? FallEventRepository();
    _reload();
  }

  void _reload() => _event = _repository.getById(widget.eventId);

  Future<void> _acknowledge() async {
    setState(() => _saving = true);
    try {
      await _repository.acknowledge(widget.eventId);
      setState(_reload);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('확인 상태를 저장하지 못했습니다. 네트워크를 확인해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('낙상 이벤트 상세')),
      body: FutureBuilder<FallEvent?>(
        future: _event,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(onRetry: () => setState(_reload));
          }
          final event = snapshot.data;
          if (event == null) {
            return const Center(child: Text('해당 낙상 이벤트 문서가 없습니다.'));
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _DetailRow(
                label: '감지 시각',
                value: _formatDateTime(event.detectedAt),
              ),
              _DetailRow(label: '카메라 위치', value: event.cameraId),
              _DetailRow(
                label: 'YOLO 신뢰도',
                value: _formatConfidence(event.confidence),
              ),
              _DetailRow(
                label: '하강 거리',
                value: event.dropPixels == null
                    ? '-'
                    : '${event.dropPixels!.toStringAsFixed(1)} px',
              ),
              _DetailRow(
                label: '확인 여부',
                value: event.acknowledged ? '확인 완료' : '미확인',
              ),
              // TODO: snapshotPath는 Raspberry Pi 로컬 경로다. Firebase Storage
              // 업로드 및 접근 URL이 제공될 때 이미지 UI를 추가한다.
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: event.acknowledged || _saving ? null : _acknowledge,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(event.acknowledged ? '확인 완료' : '확인했습니다'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({this.onRetry});
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('데이터를 불러오지 못했습니다. 네트워크를 확인해 주세요.'),
        if (onRetry != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ],
    ),
  );
}

String _formatConfidence(double? value) =>
    value == null ? '-' : '${(value * 100).toStringAsFixed(1)}%';

String _formatDateTime(DateTime? value) {
  if (value == null) return '-';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}.${two(value.month)}.${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}
