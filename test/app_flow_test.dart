import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photon_chat/e2e.dart';
import 'package:photon_chat/fip.dart';
import 'package:photon_chat/knk_api.dart';
import 'package:photon_chat/local_store.dart';
import 'package:photon_chat/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const server = 'https://test.onrender.com';

/// Bellekte çalışan küçük sahte sunucu: uygulamanın kullandığı uç noktaları taklit eder.
class FakeServer {
  final users = <String, Map<String, dynamic>>{};
  final chats = <String, List<Map<String, dynamic>>>{};
  final requests = <String, List<Map<String, dynamic>>>{};
  final deactivated = <String>{};
  int calls = 0;
  bool down = false;

  late final client = MockClient((req) async {
    calls++;
    if (down) throw http.ClientException('offline');
    final path = req.url.path;
    final body = req.body.isEmpty ? null : jsonDecode(req.body);
    http.Response json(Object o) => http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json; charset=utf-8'});

    if (path == '/health') return json({'app': 'photon-chat', 'ok': true});
    if (path == '/presence') { users[body['fipId']] = Map<String, dynamic>.from(body); return http.Response('OK', 200); }
    if (path.startsWith('/registry/')) return http.Response('OK', 200);
    if (path.startsWith('/lookup/')) {
      final code = path.split('/').last;
      final u = users.values.where((u) => u['code'] == code).firstOrNull;
      return u == null ? http.Response('Not Found', 404) : json(u);
    }
    if (path.startsWith('/requests/')) return json(requests[path.split('/')[2]] ?? []);
    if (path.startsWith('/accepted/')) return json([]);
    if (path == '/status') {
      final ids = List<String>.from(body['fipIds']);
      return json({'active': ids.where(users.containsKey).toList(), 'deactivated': ids.where(deactivated.contains).toList()});
    }
    if (path.startsWith('/typing/')) return req.method == 'GET' ? json([]) : http.Response('OK', 200);
    if (path.startsWith('/chat/')) {
      final key = path.split('/').last;
      if (req.method == 'GET') return json(chats[key] ?? []);
      if (req.method == 'POST') { (chats[key] ??= []).add(Map<String, dynamic>.from(body)); return http.Response('OK', 200); }
      chats.remove(key);
      return http.Response('OK', 200);
    }
    return http.Response('Not Found', 404);
  });
}

void _noError(WidgetTester tester) {
  final e = tester.takeException();
  if (e is FlutterError) fail(e.toStringDeep());
  expect(e, isNull);
}

Future<void> _disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late FakeServer fake;

  setUp(() {
    fake = FakeServer();
    KnkApi.client = fake.client;
  });

  testWidgets('first run: guide -> server setup -> identity -> contacts, and it all persists', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const KnkApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('Numaran yok.'), findsOneWidget);
    await tester.tap(find.text('Atla'));
    await tester.pumpAndSettle();

    expect(find.text('Mesajların nerede beklesin?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'test.onrender.com/');
    await tester.tap(find.text('Bağlan'));
    await tester.pumpAndSettle();

    expect(find.text('Kimliğin bu cihazda doğuyor.'), findsOneWidget);
    // Önizlemedeki kod, oluşturulan kimliğin kodu olmalı
    final previewCode = (tester.widget<Text>(find.byWidgetPredicate(
            (w) => w is Text && w.data != null && RegExp(r'^\d{5}$').hasMatch(w.data!))))
        .data!;
    await tester.enterText(find.byType(TextField), 'Ali');
    await tester.pump();
    await tester.ensureVisible(find.text('Kimliği oluştur'));
    await tester.tap(find.text('Kimliği oluştur'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('SENİN KODUN'), findsOneWidget);
    expect(find.text(previewCode), findsOneWidget);

    expect(await LocalStore.loadMyServerUrl(), server);
    expect((await LocalStore.loadIdentity())!.code, previewCode);
    // Kimlik public key ile sunucuya kaydoldu
    final me = fake.users.values.single;
    expect(me['name'], 'Ali');
    expect(me['publicKey'], isNotNull);

    await _disposeApp(tester);
  });

  testWidgets('returning user goes straight to contacts (server url is remembered)', (tester) async {
    final fip = FipBlock.generate();
    SharedPreferences.setMockInitialValues({
      'knk_guide_seen_v1': true,
      'knk_my_server_url_v1': server,
      'knk_identity_v1': jsonEncode(fip.toJson()),
      'knk_display_name_v1': 'Ali',
    });
    await tester.pumpWidget(const KnkApp());
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Mesajların nerede beklesin?'), findsNothing);
    expect(find.text('SENİN KODUN'), findsOneWidget);
    // Ana ekranın içeriği gerçekten görünür olmalı: alt eylem şeridi ekranı kaplamamalı.
    final bar = tester.getRect(find.byType(BottomAppBar).evaluate().isEmpty
        ? find.ancestor(of: find.text('Kişi ekle'), matching: find.byType(SafeArea)).first
        : find.byType(BottomAppBar));
    expect(bar.height, lessThan(120));
    expect(tester.getRect(find.text('SENİN KODUN')).top, lessThan(bar.top));
    expect(tester.hitTestOnBinding(tester.getCenter(find.text('SENİN KODUN'))).path.any(
        (e) => e.target is RenderParagraph), isTrue);
    await _disposeApp(tester);
  });

  testWidgets('network outage never deletes contacts', (tester) async {
    final fip = FipBlock.generate();
    SharedPreferences.setMockInitialValues({
      'knk_guide_seen_v1': true,
      'knk_my_server_url_v1': server,
      'knk_identity_v1': jsonEncode(fip.toJson()),
      'knk_display_name_v1': 'Ali',
      'knk_contacts_v1': jsonEncode([
        {'fipId': 'fip_bora', 'name': 'Bora', 'code': '22222', 'serverUrl': server, 'status': 'on'},
      ]),
    });
    fake.down = true;
    await tester.pumpWidget(const KnkApp());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 5));
    }
    expect(find.text('Bora'), findsOneWidget);
    expect(await LocalStore.loadContacts(), hasLength(1));
    // Sunucu "kayıtlı değil" dese bile (ör. yeniden başladı) kişi silinmez
    fake.down = false;
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 5));
    }
    expect(find.text('Bora'), findsOneWidget);
    // Yalnızca hesabını sildiyse kaldırılır
    fake.deactivated.add('fip_bora');
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 5));
    }
    expect(find.text('Bora'), findsNothing);
    await _disposeApp(tester);
  });

  testWidgets('sending a chat message encrypts it end-to-end and shows it', (tester) async {
    final fip = FipBlock.generate();
    final bora = FipBlock.generate();
    SharedPreferences.setMockInitialValues({
      'knk_guide_seen_v1': true,
      'knk_my_server_url_v1': server,
      'knk_identity_v1': jsonEncode(fip.toJson()),
      'knk_display_name_v1': 'Ali',
      'knk_contacts_v1': jsonEncode([
        {'fipId': bora.fipId, 'name': 'Bora', 'code': bora.code, 'serverUrl': server, 'status': 'on'},
      ]),
    });
    final boraPub = await tester.runAsync(() async {
      await ensureE2EKeypair();
      return getMyPublicKeyBase64(); // test için kendi anahtarımızı Bora'nınki gibi kullan
    });
    fake.users[bora.fipId] = {'fipId': bora.fipId, 'code': bora.code, 'name': 'Bora', 'publicKey': boraPub, 'serverUrl': server};

    await tester.pumpWidget(const KnkApp());
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Bora'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('uçtan uca şifreli'), findsOneWidget);
    expect(find.text('Bu sohbet temiz.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Selam Bora, tamam mı?');
    // Klavyeden (Enter) gönder; odak kutuda kalmalı ki art arda yazılabilsin
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 300));

    // Ekranda düz metin (küfür filtresi "tamam"ı bozmamalı), sunucuda şifreli metin
    expect(find.text('Selam Bora, tamam mı?'), findsOneWidget);
    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, isEmpty);
    final stored = fake.chats[chatKeyFor(fip.fipId, bora.fipId)]!;
    expect(stored, hasLength(1)); // aynı sunucu: iki kez yazılmaz
    expect(stored.single['text'], startsWith(e2ePrefix));
    expect(stored.single['text'], isNot(contains('Selam')));

    // Poll sonrası mesaj kaybolmamalı
    await tester.pump(const Duration(seconds: 3));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Selam Bora, tamam mı?'), findsOneWidget);

    await _disposeApp(tester);
  });

  testWidgets('screens render without overflow on a small phone (320x568)', (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final fip = FipBlock.generate();
    SharedPreferences.setMockInitialValues({
      'knk_guide_seen_v1': true,
      'knk_my_server_url_v1': server,
      'knk_identity_v1': jsonEncode(fip.toJson()),
      'knk_display_name_v1': 'Ali',
      'knk_contacts_v1': jsonEncode([
        {'fipId': 'fip_1', 'name': 'Çok Uzun Bir İsim Soyisim Örneği 😀', 'code': '11111', 'serverUrl': server, 'status': 'on'},
        {'fipId': 'fip_2', 'name': 'Bekleyen Davet Sahibi Uzun İsim', 'code': '22222', 'serverUrl': server, 'status': 'pending_in'},
        {'fipId': 'fip_3', 'name': 'Giden Davet Uzun İsim Örneği', 'code': '33333', 'serverUrl': server, 'status': 'pending_out'},
      ]),
      'knk_groups_v1': jsonEncode([
        {'groupId': 'g1', 'groupCode': '1234567', 'name': 'Çok uzun bir grup adı örneği burada', 'ownerFipId': fip.fipId, 'ownerServerUrl': server, 'isOwner': true, 'members': []},
      ]),
    });
    await tester.pumpWidget(const KnkApp());
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    _noError(tester);

    // Ayarlar
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Ayarlar'), findsOneWidget);
    _noError(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Kişi ekle
    await tester.tap(find.text('Kişi ekle'));
    await tester.pumpAndSettle();
    _noError(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Pulse AI
    await tester.tap(find.text('Pulse AI'));
    await tester.pumpAndSettle();
    _noError(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await _disposeApp(tester);
  });

  testWidgets('guide and server setup fit on a small phone', (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const KnkApp());
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      _noError(tester);
      await tester.tap(find.text(i == 4 ? 'Başla' : 'Devam'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Mesajların nerede beklesin?'), findsOneWidget);
    // Sunucuya ulaşılamazsa anlaşılır bir hata gösterilir, uygulama çökmez
    fake.down = true;
    await tester.enterText(find.byType(TextField), 'https://yok.onrender.com');
    await tester.ensureVisible(find.text('Bağlan'));
    await tester.tap(find.text('Bağlan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('bağlanılamadı'), findsOneWidget);
    _noError(tester);
    await _disposeApp(tester);
  });

  testWidgets('safety number can be compared and marked verified from the chat', (tester) async {
    final fip = FipBlock.generate();
    final bora = FipBlock.generate();
    final boraPub = await tester.runAsync(() async {
      final kp = await X25519().newKeyPair();
      return base64.encode((await kp.extractPublicKey()).bytes);
    });
    SharedPreferences.setMockInitialValues({
      'knk_guide_seen_v1': true,
      'knk_my_server_url_v1': server,
      'knk_identity_v1': jsonEncode(fip.toJson()),
      'knk_display_name_v1': 'Ali',
      'knk_contacts_v1': jsonEncode([
        {'fipId': bora.fipId, 'name': 'Bora', 'code': bora.code, 'serverUrl': server, 'status': 'on', 'publicKey': boraPub},
      ]),
    });
    await tester.pumpWidget(const KnkApp());
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Bora'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.gpp_maybe_outlined), findsWidgets);

    await tester.tap(find.byTooltip('Güvenlik numarası'));
    // Numara ayrı isolate'te hesaplanır: gerçek zamanda bekle
    for (var i = 0; i < 50 && find.byKey(const ValueKey('safety-group-11')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Doğrulanmadı'), findsOneWidget);
    _noError(tester);
    final groups = [for (var i = 0; i < 12; i++) tester.widget<Text>(find.byKey(ValueKey('safety-group-$i'))).data!];
    expect(groups, hasLength(12));

    // Ekrandaki numara, Bora'nın cihazında hesaplanacak numarayla aynı olmalı
    final myPub = await tester.runAsync(getMyPublicKeyBase64);
    final onBora = safetyNumber(myFipId: bora.fipId, myPublicKey: boraPub!, theirFipId: fip.fipId, theirPublicKey: myPub!);
    expect(groups.join(), onBora);

    await tester.ensureVisible(find.textContaining('doğrulandı olarak işaretle'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('doğrulandı olarak işaretle'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Doğrulandı'), findsOneWidget);
    expect((await tester.runAsync(LocalStore.loadVerifiedKeys))![bora.fipId], boraPub);

    await tester.pageBack();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.verified_user_outlined), findsWidgets);
    expect(find.text('doğrulandı'), findsOneWidget);
    await _disposeApp(tester);
  });
}
