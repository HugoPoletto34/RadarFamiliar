import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../controllers/radar_controller.dart';
import '../models/member_location.dart';
import 'avatar_style.dart';
import 'share_sheet.dart';

/// Lista recolhível dos membros sobre o mapa. Tocar foca a pessoa.
class MembersPanel extends StatefulWidget {
  const MembersPanel({
    super.key,
    required this.controller,
    required this.onFocus,
  });

  final RadarController controller;

  /// Recebe o `userId` do membro ou `'me'`.
  final ValueChanged<String> onFocus;

  @override
  State<MembersPanel> createState() => _MembersPanelState();
}

class _MembersPanelState extends State<MembersPanel> {
  static const _width = 230.0;
  static const _maxListHeight = 220.0;

  /// Mesma altura do `FloatingActionButton.small` do outro canto.
  static const _chipHeight = 40.0;
  static const _chipAvatars = 3;

  bool _open = true;

  void _toggle() => setState(() => _open = !_open);

  List<_Entry> _entries() {
    final c = widget.controller;
    final me = c.myPosition;
    return [
      _Entry(
        id: 'me',
        name: 'Você',
        initial: 'Eu',
        color: meColor,
        on: c.sharing.on && !c.sharing.expired,
        status: shortSharingLabel(c.sharing),
        updated: me == null ? null : seenAgo(me.timestamp),
        canFocus: me != null,
      ),
      for (final f in c.friends)
        _Entry(
          id: f.userId,
          name: f.name,
          initial: f.initial,
          color: c.colorOf(f.userId),
          on: f.isSharing,
          status: _statusOf(f),
          updated: f.hasPosition ? seenAgo(f.lastSeenAt) : null,
          canFocus: f.hasPosition,
        ),
    ];
  }

  String _statusOf(MemberLocation m) {
    if (m.status == 'paused') return 'Pausado';
    if (!m.isSharing) return 'Não compartilhando';
    if (!m.hasPosition) return 'Compartilhe para ver';
    return 'Compartilhando';
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomLeft,
      child: _open ? _expanded(context, entries) : _collapsed(context, entries),
    );
  }

  Widget _collapsed(BuildContext context, List<_Entry> entries) {
    final scheme = Theme.of(context).colorScheme;
    final shown = entries.take(_chipAvatars).toList();
    final extra = entries.length - shown.length;
    const size = 28.0;
    const step = 20.0;
    final slots = shown.length + (extra > 0 ? 1 : 0);

    return Material(
      color: scheme.surface.withValues(alpha: 0.95),
      elevation: 2,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _toggle,
        child: Tooltip(
          message: 'Mostrar membros',
          child: SizedBox(
            height: _chipHeight,
            child: Padding(
              padding: const EdgeInsets.only(left: 6, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: size + step * (slots - 1),
                    height: size,
                    child: Stack(
                      // Ordem inversa: o avatar da esquerda fica por cima e
                      // não esconde a bolinha de status.
                      children: [
                        if (extra > 0)
                          Positioned(
                            left: step * shown.length,
                            child: _Bubble(
                              size: size,
                              color: scheme.surfaceContainerHighest,
                              child: Text(
                                '+$extra',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        for (var i = shown.length - 1; i >= 0; i--)
                          Positioned(
                            left: step * i,
                            child: _Avatar(entry: shown[i], radius: size / 2),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.expand_less,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _expanded(BuildContext context, List<_Entry> entries) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: _width,
      child: Material(
        color: scheme.surface.withValues(alpha: 0.95),
        elevation: 2,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.spaceMd - 4,
                  vertical: AppDimens.spaceSm,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people_alt_outlined, size: 18),
                    const SizedBox(width: AppDimens.spaceSm),
                    Expanded(
                      child: Text(
                        'Membros (${entries.length})',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Icon(Icons.expand_more, size: 20),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _maxListHeight),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  vertical: AppDimens.spaceXs,
                ),
                children: [
                  for (final e in entries)
                    _MemberRow(
                      entry: e,
                      onTap: e.canFocus ? () => widget.onFocus(e.id) : null,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Entry {
  const _Entry({
    required this.id,
    required this.name,
    required this.initial,
    required this.color,
    required this.on,
    required this.status,
    required this.canFocus,
    this.updated,
  });

  final String id;
  final String name;
  final String initial;
  final Color color;
  final bool on;
  final String status;
  final bool canFocus;

  /// Texto relativo da última posição ("há 2 min"). Nulo sem posição.
  final String? updated;
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.size, required this.color, required this.child});

  final double size;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 2,
        ),
      ),
      child: child,
    );
  }
}

/// Avatar com a bolinha de status: verde compartilhando, cinza desligado.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.entry, required this.radius});

  final _Entry entry;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dot = radius * 0.7;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _Bubble(
          size: radius * 2,
          color: entry.color,
          child: Text(
            entry.initial,
            style: TextStyle(
              fontSize: radius * 0.75,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              color: entry.on ? AppColors.success : scheme.outline,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.surface, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.entry, this.onTap});

  final _Entry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final last = entry.updated;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.spaceMd - 4,
          vertical: 6,
        ),
        child: Row(
          children: [
            _Avatar(entry: entry, radius: 16),
            const SizedBox(width: AppDimens.spaceSm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    entry.status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                  if (last != null && last.isNotEmpty)
                    Text(
                      'Atualizado $last',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.my_location, size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
