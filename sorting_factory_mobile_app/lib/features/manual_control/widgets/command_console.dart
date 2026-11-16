import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/communication/communication_log.dart';
import '../../../core/communication/communication_scope.dart';
import '../../../core/communication/connection_status.dart';
import '../../../core/communication/robot_command.dart';
import '../../../core/communication/robot_communication_service.dart';
import '../../../core/communication/sfra_protocol.dart';
import '../../../shared/widgets/page_body.dart';

/// Terminal-like panel showing every command sent to the ESP32 and every
/// reply it notified, with an input to send raw protocol text.
class CommandConsole extends StatefulWidget {
  const CommandConsole({super.key, required this.logHeight});

  /// Height of the scrollable history when the panel is expanded.
  final double logHeight;

  @override
  State<CommandConsole> createState() => _CommandConsoleState();
}

class _CommandConsoleState extends State<CommandConsole> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _expanded = true;
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _input.text.trim();
    final service = CommunicationScope.read(context);
    if (text.isEmpty || _sending || !service.isConnected) return;

    setState(() => _sending = true);
    try {
      await service.send(RawTextCommand(text));
      _input.clear();
    } on CommunicationException {
      // Already recorded in the log shown right above the input.
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (mounted) _focus.requestFocus();
  }

  Future<void> _copyLog(CommunicationLog log) async {
    final text = log.entries.map(_ConsoleLine.plainText).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Log copied')));
  }

  @override
  Widget build(BuildContext context) {
    final service = CommunicationScope.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: PageBody(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListenableBuilder(
                listenable: service.log,
                builder: (context, _) => _ConsoleHeader(
                  activity: service.activity,
                  expanded: _expanded,
                  lastEntry: service.log.isEmpty
                      ? null
                      : service.log.entries.last,
                  onToggle: () => setState(() => _expanded = !_expanded),
                  onClear: service.log.isEmpty ? null : service.log.clear,
                  onCopy: service.log.isEmpty
                      ? null
                      : () => _copyLog(service.log),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: SizedBox(
                              height: widget.logHeight,
                              child: _ConsoleLog(log: service.log),
                            ),
                          ),
                          _ConsoleInput(
                            controller: _input,
                            focusNode: _focus,
                            connected: service.isConnected,
                            sending: _sending,
                            onSubmit: _submit,
                          ),
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsoleHeader extends StatelessWidget {
  const _ConsoleHeader({
    required this.activity,
    required this.expanded,
    required this.lastEntry,
    required this.onToggle,
    required this.onClear,
    required this.onCopy,
  });

  final RobotActivity activity;
  final bool expanded;
  final CommunicationLogEntry? lastEntry;
  final VoidCallback onToggle;
  final VoidCallback? onClear;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            Icon(Icons.terminal_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Command window',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!expanded && lastEntry != null)
                          Text(
                            _ConsoleLine.plainText(lastEntry!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _ConsoleLine.mono(theme).copyWith(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ActivityPill(activity: activity),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy log',
              visualDensity: VisualDensity.compact,
              onPressed: onCopy,
              icon: const Icon(Icons.copy_all_rounded, size: 20),
            ),
            IconButton(
              tooltip: 'Clear log',
              visualDensity: VisualDensity.compact,
              onPressed: onClear,
              icon: const Icon(Icons.delete_sweep_outlined, size: 20),
            ),
            IconButton(
              tooltip: expanded ? 'Collapse' : 'Expand',
              visualDensity: VisualDensity.compact,
              onPressed: onToggle,
              icon: Icon(
                expanded
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_up_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityPill extends StatelessWidget {
  const _ActivityPill({required this.activity});

  final RobotActivity activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = switch (activity) {
      RobotActivity.offline => scheme.outline,
      RobotActivity.idle => scheme.primary,
      RobotActivity.awaitingResponse || RobotActivity.moving => scheme.tertiary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (activity.isBusy)
            SizedBox.square(
              dimension: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          else
            Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(
            activity.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsoleLog extends StatelessWidget {
  const _ConsoleLog({required this.log});

  final CommunicationLog log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ListenableBuilder(
          listenable: log,
          builder: (context, _) {
            final entries = log.entries;
            if (entries.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Sent commands and ESP32 replies will appear here.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }
            // Reversed so the newest line stays pinned to the bottom.
            return SelectionArea(
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: entries.length,
                itemBuilder: (context, index) =>
                    _ConsoleLine(entry: entries[entries.length - 1 - index]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ConsoleLine extends StatelessWidget {
  const _ConsoleLine({required this.entry});

  final CommunicationLogEntry entry;

  static TextStyle mono(ThemeData theme) =>
      (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
        fontFamily: 'monospace',
        fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
        height: 1.35,
      );

  static String _tag(LogDirection direction) => switch (direction) {
    LogDirection.sent => 'TX',
    LogDirection.received => 'RX',
    LogDirection.info => '--',
    LogDirection.error => '!!',
  };

  static String _time(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  static String plainText(CommunicationLogEntry e) =>
      '${_time(e.time)} ${_tag(e.direction)} ${e.text}';

  Color _color(ColorScheme scheme, Brightness brightness) =>
      switch (entry.direction) {
        LogDirection.sent => scheme.primary,
        LogDirection.info => scheme.onSurfaceVariant,
        LogDirection.error => scheme.error,
        LogDirection.received => switch (entry.response) {
          DeviceResponse.done =>
            brightness == Brightness.dark
                ? const Color(0xFF81C784)
                : const Color(0xFF2E7D32),
          DeviceResponse.error => scheme.error,
          DeviceResponse.moving => scheme.tertiary,
          _ => scheme.secondary,
        },
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = mono(theme);
    final color = _color(scheme, theme.brightness);
    final isMessage =
        entry.direction == LogDirection.sent ||
        entry.direction == LogDirection.received;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(
              text: '${_time(entry.time)} ',
              style: TextStyle(color: scheme.outline),
            ),
            TextSpan(
              text: '${_tag(entry.direction)} ',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: entry.text,
              style: TextStyle(
                color: isMessage ? color : scheme.onSurfaceVariant,
                fontWeight: isMessage ? FontWeight.w600 : FontWeight.w400,
                fontStyle: isMessage ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsoleInput extends StatelessWidget {
  const _ConsoleInput({
    required this.controller,
    required this.focusNode,
    required this.connected,
    required this.sending,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool connected;
  final bool sending;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final text = value.text.trim();
          final problem = text.isEmpty ? null : SfraProtocol.validate(text);
          final canSend = connected && !sending && text.isNotEmpty;

          return Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('console-input'),
                  controller: controller,
                  focusNode: focusNode,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSubmit(),
                  inputFormatters: [
                    // The firmware only accepts printable ASCII.
                    FilteringTextInputFormatter.allow(RegExp(r'[ -~]')),
                    LengthLimitingTextInputFormatter(200),
                  ],
                  style: _ConsoleLine.mono(
                    Theme.of(context),
                  ).copyWith(fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: connected
                        ? 'e.g. ${SfraProtocol.example}'
                        : 'Connect to send commands',
                    prefixIcon: const Icon(Icons.chevron_right_rounded),
                    suffixIcon: text.isEmpty
                        ? null
                        : Tooltip(
                            message:
                                problem ??
                                'Valid command (${SfraProtocol.formatHint})',
                            triggerMode: TooltipTriggerMode.tap,
                            child: Icon(
                              problem == null
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.warning_amber_rounded,
                              color: problem == null
                                  ? scheme.primary
                                  : scheme.error,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: connected ? 'Send command' : 'Not connected',
                onPressed: canSend ? onSubmit : null,
                icon: sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          );
        },
      ),
    );
  }
}
