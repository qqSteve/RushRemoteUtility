import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import '../pages/desktop_setting_page.dart';
import 'rush_dashboard.dart';
import 'rush_tools.dart';

class RushHome extends StatefulWidget {
  final VoidCallback openClassic;
  const RushHome({super.key, required this.openClassic});
  @override
  State<RushHome> createState() => _RushHomeState();
}

class _RushHomeState extends State<RushHome> {
  static const listener = 'rush-home';
  List<String> ids = [];
  final names = <String, String>{};
  final statuses = <String, (bool, DateTime)>{};
  final pending = <String>{};
  Timer? timer;
  int generation = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    platformFFI.registerEventHandler('callback_query_onlines', listener,
        (evt) async {
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        for (final flag in [true, false]) {
          for (final id in (evt[flag ? 'onlines' : 'offlines'] as String? ?? '')
              .split(',')) {
            if (ids.contains(id)) statuses[id] = (flag, now);
          }
        }
      });
    });
    platformFFI.registerEventHandler('load_fav_peers', listener, (evt) async {
      final payload = evt['peers'] as String?;
      final rows =
          payload == null || payload.isEmpty ? [] : jsonDecode(payload);
      if (!mounted || rows is! List) return;
      for (final row in rows.whereType<Map>()) {
        final id = row['id'];
        if (id is String) {
          final alias = row['alias'] as String? ?? '';
          names[id] =
              alias.isNotEmpty ? alias : row['hostname'] as String? ?? '';
        }
      }
      await refresh();
    });
    refresh();
    bind.mainLoadFavPeers();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => query());
  }

  Future<void> refresh() async {
    final request = ++generation;
    try {
      final next = await bind.mainGetFav();
      if (!mounted || request != generation) return;
      setState(() {
        ids = next.toSet().toList();
        loading = false;
        statuses.removeWhere((k, _) => !ids.contains(k));
      });
      query();
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        showToast(e.toString());
      }
    }
  }

  void query() {
    if (!mounted || ids.isEmpty) return;
    final now = DateTime.now();
    setState(() => statuses.removeWhere(
        (_, v) => now.difference(v.$2) > const Duration(minutes: 1)));
    bind.queryOnlines(ids: ids);
  }

  @override
  void dispose() {
    timer?.cancel();
    for (final key in ['load_fav_peers', 'callback_query_onlines']) {
      platformFFI.unregisterEventHandler(key, listener);
    }
    super.dispose();
  }

  String get local {
    final text = gFFI.serverModel.serverId.text;
    return text == translate('Generating ...') ? '' : trimID(text);
  }

  Future<void> input({RushDevice? existing, bool direct = false}) async {
    final form = GlobalKey<FormState>();
    var id = existing?.id ?? '', name = existing?.name ?? '';
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(direct
                    ? 'Подключиться по ID'
                    : existing == null
                        ? 'Добавить компьютер'
                        : 'Переименовать компьютер'),
                content: Form(
                    key: form,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextFormField(
                          initialValue: id,
                          readOnly: existing != null,
                          autofocus: existing == null,
                          decoration:
                              const InputDecoration(labelText: 'Удалённый ID'),
                          onChanged: (v) => id = v,
                          validator: (v) {
                            final value = trimID((v ?? '').trim());
                            if (value.isEmpty) return 'Введите ID';
                            if (value == local) return 'Это ID текущего ПК';
                            if (!direct &&
                                existing == null &&
                                !RegExp(r'^[a-zA-Z0-9_-]{1,64}$')
                                    .hasMatch(value))
                              return 'Проверьте ID устройства';
                            return null;
                          }),
                      if (!direct)
                        TextFormField(
                            initialValue: name,
                            autofocus: existing != null,
                            decoration: const InputDecoration(
                                labelText: 'Название компьютера'),
                            onChanged: (v) => name = v),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Отмена')),
                  FilledButton(
                      onPressed: () {
                        if (form.currentState!.validate())
                          Navigator.pop(ctx, true);
                      },
                      child: Text(direct ? 'Подключиться' : 'Сохранить')),
                ]));
    if (!mounted || ok != true) return;
    id = trimID(id.trim());
    if (direct) {
      await device(
          RushDevice(id, id, formatID(id), null), DeviceAction.connect);
      return;
    }
    final list = (await bind.mainGetFav()).toList();
    await bind.mainSetPeerAlias(id: id, alias: name.trim());
    names[id] = name.trim();
    if (!list.contains(id)) {
      list.add(id);
      await bind.mainStoreFav(favs: list);
    }
    await refresh();
    await bind.mainLoadFavPeers();
  }

  Future<void> action(RushAction a) async {
    try {
      switch (a) {
        case RushAction.copy:
          if (local.isNotEmpty) {
            await Clipboard.setData(ClipboardData(text: local));
            showToast('ID скопирован');
          }
          break;
        case RushAction.add:
          await input();
          break;
        case RushAction.direct:
          await input(direct: true);
          break;
        case RushAction.legacy:
          widget.openClassic();
          break;
        case RushAction.settings:
          DesktopSettingPage.switch2page(SettingsTabKey.general);
          break;
        case RushAction.prepare:
          await showRushTool(context, RushTool.prepare);
          break;
        case RushAction.diagnose:
          await showRushTool(context, RushTool.diagnose);
          break;
        case RushAction.updates:
          await showRushTool(context, RushTool.updates);
          break;
      }
    } catch (e) {
      if (mounted) showToast(e.toString());
    }
  }

  Future<void> device(RushDevice p, DeviceAction a) async {
    if (!pending.add(p.id)) return;
    setState(() {});
    try {
      switch (a) {
        case DeviceAction.connect:
          await connect(context, p.id);
          break;
        case DeviceAction.wake:
          final code = await bind.mainWakeSavedPeer(id: p.id);
          if (mounted)
            showToast(code == 'sent'
                ? 'Пакет пробуждения отправлен'
                : code == 'missing-mac'
                    ? 'MAC-адрес неизвестен. Найдите включённый ПК во вкладке локальной сети.'
                    : 'Не удалось отправить пакет пробуждения');
          break;
        case DeviceAction.edit:
          await input(existing: p);
          break;
        case DeviceAction.remove:
          final list = (await bind.mainGetFav()).toList()..remove(p.id);
          await bind.mainStoreFav(favs: list);
          await refresh();
          await bind.mainLoadFavPeers();
          break;
      }
    } catch (e) {
      if (mounted) showToast(e.toString());
    } finally {
      pending.remove(p.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
          valueListenable: gFFI.serverModel.serverId,
          builder: (_, __, ___) => RushDashboard(
              hostname: Platform.localHostname,
              localId: formatID(local),
              loading: loading,
              pending: pending,
              devices: [
                for (final id in ids)
                  RushDevice(id, (names[id] ?? '').isEmpty ? id : names[id]!,
                      formatID(id), statuses[id]?.$1)
              ],
              onAction: action,
              onDevice: device));
}
