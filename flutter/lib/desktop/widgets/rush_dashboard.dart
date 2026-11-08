import 'package:flutter/material.dart';

const _orange = Color(0xffff8b2b);
const _base = Color(0xff101114);
const _panel = Color(0xff191b20);
const _line = Color(0xff383b42);
const _muted = Color(0xffb6b8c0);
const _white = Color(0xfff4f4f4);

class RushDevice {
  final String id, name, displayId;
  final bool? online;
  const RushDevice(this.id, this.name, this.displayId, this.online);
}

enum RushAction {
  copy,
  direct,
  add,
  legacy,
  settings,
  prepare,
  diagnose,
  updates
}

enum DeviceAction { connect, wake, edit, remove }

class RushDashboard extends StatelessWidget {
  final String hostname, localId;
  final List<RushDevice> devices;
  final bool loading;
  final Set<String> pending;
  final ValueChanged<RushAction> onAction;
  final void Function(RushDevice, DeviceAction) onDevice;
  const RushDashboard(
      {super.key,
      required this.hostname,
      required this.localId,
      required this.devices,
      required this.loading,
      required this.pending,
      required this.onAction,
      required this.onDevice});

  Widget utility(
          RushAction action, IconData icon, String label, bool compact) =>
      compact
          ? IconButton(
              tooltip: label,
              onPressed: () => onAction(action),
              icon: Icon(icon))
          : TextButton.icon(
              onPressed: () => onAction(action),
              icon: Icon(icon, size: 18),
              label: Text(label));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
        data: theme.copyWith(
          colorScheme:
              const ColorScheme.dark(primary: _orange, surface: _panel),
          textTheme:
              theme.textTheme.apply(bodyColor: _white, displayColor: _white),
          iconTheme: const IconThemeData(color: _muted),
          textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: _white)),
        ),
        child: Material(
            color: _base,
            child: LayoutBuilder(builder: (context, box) {
              final tight = box.maxWidth < 720;
              final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final compact = tight || scale > 1.3;
              return Row(children: [
                Container(
                    width: tight ? 50 : 72,
                    decoration: const BoxDecoration(
                        border: Border(right: BorderSide(color: _line))),
                    child: Column(children: [
                      const SizedBox(height: 16),
                      Image.asset('assets/rush-brand.webp',
                          height: 40,
                          width: 40,
                          semanticLabel: 'RushRemoteUtility'),
                      const SizedBox(height: 20),
                      Semantics(
                          selected: true,
                          label: 'Мои компьютеры',
                          child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: const BoxDecoration(
                                  color: Color(0xff35251a),
                                  border: Border(
                                      left: BorderSide(
                                          width: 3, color: _orange))),
                              child: const Icon(Icons.desktop_windows_outlined,
                                  color: _orange))),
                      utility(RushAction.legacy, Icons.swap_horiz,
                          'Подключения и доступ', true),
                      utility(RushAction.prepare, Icons.settings_remote,
                          'Подготовить ПК', true),
                      const Spacer(),
                      utility(RushAction.settings, Icons.settings_outlined,
                          'Настройки', true),
                      const SizedBox(height: 8),
                    ])),
                Expanded(
                    child: Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: tight ? 12 : 24),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 12),
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 5),
                                  decoration: BoxDecoration(
                                      color: _panel,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: _line)),
                                  child: Wrap(
                                      spacing: 16,
                                      runSpacing: 0,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        const Icon(
                                            Icons.desktop_windows_outlined,
                                            size: 19),
                                        Text('Этот ПК · $hostname',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                        Text(
                                            localId.isEmpty
                                                ? 'Получаем ID…'
                                                : 'ID $localId',
                                            style: const TextStyle(
                                                fontFamily: 'monospace')),
                                        OutlinedButton.icon(
                                            onPressed: localId.isEmpty
                                                ? null
                                                : () =>
                                                    onAction(RushAction.copy),
                                            icon: const Icon(Icons.copy,
                                                size: 15),
                                            label: const Text('Скопировать ID'),
                                            style: OutlinedButton.styleFrom(
                                                foregroundColor: _white)),
                                      ])),
                              const SizedBox(height: 12),
                              Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  children: [
                                    Text('Мои компьютеры',
                                        style: TextStyle(
                                            color: _white,
                                            fontSize: tight ? 23 : 32,
                                            fontWeight: FontWeight.w700)),
                                    Wrap(spacing: 8, children: [
                                      utility(RushAction.direct, Icons.link,
                                          'По ID', false),
                                      ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: _orange,
                                              foregroundColor: _base),
                                          onPressed: () =>
                                              onAction(RushAction.add),
                                          icon: const Icon(Icons.add, size: 18),
                                          label: const Text('Добавить')),
                                    ]),
                                  ]),
                              const SizedBox(height: 10),
                              Expanded(
                                  child: loading
                                      ? const Center(
                                          child: CircularProgressIndicator())
                                      : devices.isEmpty
                                          ? Center(
                                              child: SingleChildScrollView(
                                                  child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                  const Text(
                                                      'Пока нет сохранённых компьютеров',
                                                      textAlign:
                                                          TextAlign.center),
                                                  TextButton(
                                                      onPressed: () => onAction(
                                                          RushAction.add),
                                                      child: const Text(
                                                          'Добавить компьютер')),
                                                ])))
                                          : LayoutBuilder(
                                              builder: (context, area) {
                                              const gap = 14.0;
                                              final columns = ((area.maxWidth +
                                                          gap) /
                                                      (315 *
                                                              scale.clamp(
                                                                  1.0, 1.7) +
                                                          gap))
                                                  .floor()
                                                  .clamp(1, 8)
                                                  .toInt();
                                              return GridView.builder(
                                                  key: const PageStorageKey(
                                                      'rush-devices'),
                                                  padding: const EdgeInsets.only(
                                                      bottom: 8),
                                                  itemCount: devices.length,
                                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                                      crossAxisCount: columns,
                                                      mainAxisSpacing: gap,
                                                      crossAxisSpacing: gap,
                                                      mainAxisExtent: (tight
                                                              ? 229
                                                              : 285) +
                                                          88 *
                                                              (scale.clamp(
                                                                      1.0, 3.0) -
                                                                  1)),
                                                  itemBuilder: (context, i) => _DeviceTile(
                                                      key: ValueKey(
                                                          devices[i].id),
                                                      peer: devices[i],
                                                      pending: pending.contains(
                                                          devices[i].id),
                                                      onAction: (a) => onDevice(
                                                          devices[i], a)));
                                            })),
                              const Divider(height: 1, color: _line),
                              Wrap(
                                  spacing: 12,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    utility(
                                        RushAction.diagnose,
                                        Icons.monitor_heart_outlined,
                                        'Диагностика',
                                        compact),
                                    utility(RushAction.updates, Icons.refresh,
                                        'Проверить обновления', compact),
                                  ]),
                            ]))),
              ]);
            })));
  }
}

class _DeviceTile extends StatelessWidget {
  final RushDevice peer;
  final bool pending;
  final ValueChanged<DeviceAction> onAction;
  const _DeviceTile(
      {super.key,
      required this.peer,
      required this.pending,
      required this.onAction});
  @override
  Widget build(BuildContext context) {
    final online = peer.online;
    final color = online == true ? const Color(0xff55d765) : _muted;
    final size =
        40.0 + (MediaQuery.textScalerOf(context).scale(16) - 16).clamp(0, 32);
    return Container(
        decoration: BoxDecoration(
            color: _panel,
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
              child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(
                child: Image.asset('assets/rush-tower.webp',
                    fit: BoxFit.contain, excludeFromSemantics: true)),
            Positioned(
                right: 0,
                top: 0,
                child: PopupMenuButton<DeviceAction>(
                    tooltip: 'Действия с устройством',
                    icon: const Icon(Icons.more_horiz, size: 18),
                    onSelected: onAction,
                    itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: DeviceAction.edit,
                              child: Text('Переименовать')),
                          PopupMenuItem(
                              value: DeviceAction.remove,
                              child: Text('Убрать из избранного')),
                        ]))
          ])),
          Row(children: [
            const Icon(Icons.desktop_windows_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Tooltip(
                    message: peer.name,
                    child: Text(peer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: _white))))
          ]),
          Text('ID ${peer.displayId}',
              maxLines: 1,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 15, color: _white)),
          Row(children: [
            Icon(Icons.circle, size: 9, color: color),
            const SizedBox(width: 7),
            Flexible(
                child: Text(
                    online == null
                        ? 'Статус неизвестен'
                        : online
                            ? 'В сети'
                            : 'Не в сети',
                    style: TextStyle(color: color, fontSize: 14)))
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: SizedBox(
                    height: size,
                    child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _orange,
                            foregroundColor: _base,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8))),
                        onPressed: pending
                            ? null
                            : () => onAction(DeviceAction.connect),
                        child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.desktop_windows_outlined, size: 17),
                              SizedBox(width: 6),
                              Text('Подключиться')
                            ]))))),
            const SizedBox(width: 8),
            SizedBox.square(
                dimension: size,
                child: Tooltip(
                    message: 'Разбудить по сети',
                    child: OutlinedButton(
                        onPressed:
                            pending ? null : () => onAction(DeviceAction.wake),
                        style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            foregroundColor: _orange,
                            side: const BorderSide(color: _orange),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8))),
                        child: const Icon(Icons.power_settings_new,
                            semanticLabel: 'Разбудить по сети')))),
          ]),
        ]));
  }
}
