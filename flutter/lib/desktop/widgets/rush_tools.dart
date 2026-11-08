import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import '../pages/desktop_setting_page.dart';

enum _Tool { peers, diagnose, prepare, updates }

const _labels = [
  'Мои компьютеры',
  'Диагностика',
  'Подготовить ПК',
  'Проверить обновления'
];
const _icons = [
  Icons.devices,
  Icons.network_check,
  Icons.settings_remote,
  Icons.system_update_alt
];

class RushTools extends StatelessWidget {
  const RushTools({super.key});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tool in _Tool.values)
            if ((tool != _Tool.peers || !bind.isIncomingOnly()) &&
                (tool != _Tool.prepare || !bind.isOutgoingOnly()))
              TextButton(
                onPressed: () => showDialog<void>(
                    context: context, builder: (_) => _ToolDialog(tool)),
                child: Row(children: [
                  Icon(_icons[tool.index], size: 17),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_labels[tool.index])),
                ]),
              ),
        ],
      );
}

class _ToolDialog extends StatefulWidget {
  final _Tool tool;
  const _ToolDialog(this.tool);
  @override
  State<_ToolDialog> createState() => _ToolState();
}

class _ToolState extends State<_ToolDialog> {
  final name = TextEditingController();
  final id = TextEditingController();
  final peers = <String, String>{};
  String result = '';
  bool busy = false;
  Timer? poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) run(refresh);
    });
  }

  @override
  void dispose() {
    poll?.cancel();
    id.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      result = 'Ошибка: $e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String> service() async {
    final sys = Platform.environment['SystemRoot']!;
    final r = await Process.run(
        '$sys/System32/WindowsPowerShell/v1.0/powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r"$s = Get-Service -Name RushRemoteUtility -ErrorAction SilentlyContinue; if ($s) { $s.Status.ToString() } else { 'Missing' }"
    ]).timeout(const Duration(seconds: 8));
    return {
          'Running': 'работает',
          'Stopped': 'остановлена',
          'Missing': 'не установлена'
        }[r.stdout.toString().trim()] ??
        'состояние неизвестно';
  }

  Future<String> release() async {
    final f = File(
        '${File(Platform.resolvedExecutable).parent.path}/rush-version.txt');
    return await f.exists()
        ? (await f.readAsString()).trim()
        : await bind.mainGetVersion();
  }

  Future<void> refresh() async {
    switch (widget.tool) {
      case _Tool.peers:
        final favorites = await bind.mainGetFav();
        peers.clear();
        for (final peer in favorites) {
          peers[peer] = bind.mainGetPeerOptionSync(id: peer, key: 'alias');
        }
        break;
      case _Tool.diagnose:
        final host = bind.mainGetOptionSync(key: 'custom-rendezvous-server');
        final relay = bind.mainGetOptionSync(key: 'relay-server');
        final status = jsonDecode(await bind.mainGetConnectStatus());
        final lines = <String>[
          'RushRemoteUtility ${await release()}',
          'Служба Windows: ${await service()}',
          'Регистрация: ${status['status_num'] == 1 ? "готов" : "нет подтверждения"}',
          'Публичный ключ: ${bind.mainGetOptionSync(key: "key").isEmpty ? "не задан" : "задан"}'
        ];
        for (final entry in {
          'ID': [host, 21116],
          'Ретранслятор': [relay, 21117]
        }.entries) {
          var addr = entry.value.first as String;
          if (addr.isEmpty && entry.key == 'Ретранслятор' && host.isNotEmpty) {
            addr = Uri.parse('tcp://$host').host;
            if (addr.contains(':')) addr = '[$addr]';
          }
          if (addr.isEmpty) {
            lines.add('${entry.key}: сервер не задан');
            continue;
          }
          try {
            final uri = Uri.parse('tcp://$addr');
            final port = uri.hasPort ? uri.port : entry.value.last as int;
            final socket = await Socket.connect(uri.host, port,
                timeout: const Duration(seconds: 4));
            socket.destroy();
            lines.add('${entry.key} $addr (TCP $port): доступен');
          } catch (_) {
            lines.add('${entry.key} $addr: TCP-соединение не удалось');
          }
        }
        result = lines.join('\n');
        break;
      case _Tool.prepare:
        final password = (await bind.mainGetPermanentPassword()).isNotEmpty;
        final mode = bind.mainGetOptionSync(key: 'approve-mode');
        final method = bind.mainGetOptionSync(key: 'verification-method');
        result = '1. Служба Windows: ${await service()}\n'
            '2. Постоянный пароль: ${password ? "задан" : "требуется настроить"}\n'
            '3. Вход без подтверждения: ${mode == "password" && method != "use-temporary-password" && password ? "настроен" : "проверьте настройки безопасности"}\n\n'
            'Для входа в отсутствие владельца выберите подтверждение по паролю и задайте уникальный постоянный пароль этому ПК.';
        break;
      case _Tool.updates:
        if (!bind.mainIsInstalled()) {
          result = 'Установите клиент, чтобы служба могла обновлять его.';
          break;
        }
        final svc = await service();
        if (svc != 'работает') {
          result = 'Служба Windows: $svc';
          break;
        }
        final stamp = DateTime.now();
        final file = File(
            "${Platform.environment['ProgramFiles']}/RushRemoteUtility Maintenance/status.txt");
        final previous = await file.exists() ? await file.lastModified() : null;
        final current = await release();
        await bind.mainSetOption(
            key: 'rush-check-request',
            value: stamp.microsecondsSinceEpoch.toString());
        result = 'Версия $current. Проверка запрошена…';
        poll?.cancel();
        poll = Timer.periodic(const Duration(seconds: 2), (t) async {
          try {
            if (await file.exists() && await file.lastModified() != previous) {
              final text = (await file.readAsString()).trim();
              if (mounted && text.isNotEmpty) setState(() => result = text);
            } else if (t.tick >= 30 && mounted) {
              setState(() => result =
                  'Служба пока не ответила. Проверьте установку в Program Files и её состояние в диагностике.');
            }
          } catch (_) {
            /* Status may be replaced while the installer is starting. */
          }
          if (t.tick >= 150) t.cancel();
        });
        break;
    }
  }

  Future<void> savePeer() async {
    final peer = id.text.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^[0-9]{6,16}$').hasMatch(peer)) {
      result = 'Введите цифровой ID компьютера';
      return;
    }
    if (peer == (await bind.mainGetMyId()).replaceAll(' ', '')) {
      result = 'Это ID текущего компьютера';
      return;
    }
    final fav = (await bind.mainGetFav()).toList();
    await bind.mainSetPeerAlias(id: peer, alias: name.text.trim());
    if (!fav.contains(peer)) {
      fav.add(peer);
      await bind.mainStoreFav(favs: fav);
    }
    await bind.mainLoadFavPeers();
    if (!mounted) return;
    id.clear();
    name.clear();
    result = '';
    await refresh();
  }

  Future<void> removePeer(String peer) async {
    final fav = (await bind.mainGetFav()).toList()..remove(peer);
    await bind.mainStoreFav(favs: fav);
    await bind.mainLoadFavPeers();
    await refresh();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_labels[widget.tool.index]),
        content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  if (widget.tool == _Tool.peers) ...[
                    TextField(
                        controller: name,
                        decoration: const InputDecoration(
                            labelText: 'Название компьютера')),
                    TextField(
                        controller: id,
                        decoration:
                            const InputDecoration(labelText: 'Удалённый ID')),
                    TextButton(
                        onPressed: busy ? null : () => run(savePeer),
                        child: const Text('Сохранить компьютер')),
                    for (final p in peers.entries)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(p.value.isEmpty ? p.key : p.value),
                          subtitle: Text(p.key),
                          onTap: () {
                            final home = Navigator.of(context).context;
                            Navigator.pop(context);
                            connect(home, p.key);
                          },
                          trailing: IconButton(
                              tooltip: 'Убрать из избранного',
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: busy
                                  ? null
                                  : () => run(() => removePeer(p.key)))),
                  ],
                  if (busy) const LinearProgressIndicator(),
                  if (result.isNotEmpty) SelectableText(result),
                  if (widget.tool == _Tool.prepare) ...[
                    if (!bind.mainIsInstalled() &&
                        !bind.isDisableInstallation())
                      TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            bind.mainGotoInstall();
                          },
                          child: const Text('Установить клиент')),
                    if (DesktopSettingPage.tabKeys
                        .contains(SettingsTabKey.safety))
                      TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            DesktopSettingPage.switch2page(
                                SettingsTabKey.safety);
                          },
                          child: const Text('Открыть настройки безопасности')),
                    TextButton(
                        onPressed: () async {
                          final mine = await bind.mainGetMyId();
                          await Clipboard.setData(ClipboardData(
                              text: '${Platform.localHostname}: $mine'));
                          showToast('Имя и ID скопированы');
                        },
                        child: const Text('Скопировать имя и ID')),
                  ],
                  if (widget.tool == _Tool.diagnose && result.isNotEmpty)
                    TextButton(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: result));
                          showToast('Отчёт скопирован');
                        },
                        child: const Text('Скопировать отчёт')),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'))
        ],
      );
}
