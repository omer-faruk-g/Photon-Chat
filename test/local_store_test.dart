import 'package:flutter_test/flutter_test.dart';
import 'package:photon_chat/fip.dart';
import 'package:photon_chat/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('server url, identity and contacts persist', () async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.saveMyServerUrl(' https://x.onrender.com ');
    expect(await LocalStore.loadMyServerUrl(), 'https://x.onrender.com');

    final fip = FipBlock.generate();
    await LocalStore.saveIdentity(fip);
    expect((await LocalStore.loadIdentity())!.code, fip.code);

    await LocalStore.saveContacts([Contact(fipId: 'fip_b', name: 'Bora', code: '22222', serverUrl: 's', status: 'on', publicKey: 'PK')]);
    final c = (await LocalStore.loadContacts()).single;
    expect(c.publicKey, 'PK');
    expect(c.status, 'on');
  });

  test('corrupt storage never crashes the app', () async {
    SharedPreferences.setMockInitialValues({
      'knk_identity_v1': '{bozuk',
      'knk_contacts_v1': '[{"fipId":"fip_ok","name":"A","code":"1","serverUrl":"s","status":"on"}, 5, {"name":"id yok"}]',
      'knk_groups_v1': 'not json',
      'knk_block_list_v1': '[1, "fip_x"]',
    });
    expect(await LocalStore.loadIdentity(), isNull);
    expect((await LocalStore.loadContacts()).map((c) => c.fipId), ['fip_ok']);
    expect(await LocalStore.loadGroups(), isEmpty);
    expect(await LocalStore.loadBlockList(), ['fip_x']);
  });

  test('old contacts without optional fields load with defaults', () async {
    SharedPreferences.setMockInitialValues({
      'knk_contacts_v1': '[{"fipId":"fip_a","name":"A","code":"12345","status":"on"}]',
    });
    final c = (await LocalStore.loadContacts()).single;
    expect(c.serverUrl, '');
    expect(c.publicKey, isNull);
  });

  test('wipeIdentity removes everything', () async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.saveMyServerUrl('https://x');
    await LocalStore.saveIdentity(FipBlock.generate());
    await LocalStore.blockUser('fip_z');
    await LocalStore.wipeIdentity();
    expect(await LocalStore.loadMyServerUrl(), isNull);
    expect(await LocalStore.loadIdentity(), isNull);
    expect(await LocalStore.loadBlockList(), isEmpty);
  });

  test('group token survives save/load; legacy groups load without one', () async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.saveGroups([
      Group(groupId: 'g1', groupCode: '1234567', name: 'G', ownerFipId: 'fip_a', ownerServerUrl: 's', isOwner: true, members: [], token: 'tok'),
      Group(groupId: 'g2', groupCode: '7654321', name: 'Eski', ownerFipId: 'fip_a', ownerServerUrl: 's', isOwner: false, members: []),
    ]);
    final groups = await LocalStore.loadGroups();
    expect(groups.map((g) => g.token), ['tok', null]);
  });
}
