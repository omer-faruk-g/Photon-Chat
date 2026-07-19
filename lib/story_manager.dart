import 'dart:convert';
import 'local_store.dart';
import 'photon_api.dart';

class StoryItem {
  final String id;
  final String authorFipId;
  final String authorName;
  final String type; // 'text' or 'image'
  final String content;
  final int ts;
  final int expiresAt;

  StoryItem({required this.id, required this.authorFipId, required this.authorName, required this.type, required this.content, required this.ts, required this.expiresAt});

  Map<String, dynamic> toJson() => {'id': id, 'authorFipId': authorFipId, 'authorName': authorName, 'type': type, 'content': content, 'ts': ts, 'expiresAt': expiresAt};
  factory StoryItem.fromJson(Map<String, dynamic> j) => StoryItem(id: j['id'], authorFipId: j['authorFipId'], authorName: j['authorName'], type: j['type'], content: j['content'], ts: j['ts'], expiresAt: j['expiresAt']);

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAt;
}

class StoryManager {
  static Future<void> postStory({required String serverUrl, required String fipId, required String authorName, required String type, required String content}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = '${fipId}_$now';
    final story = StoryItem(id: id, authorFipId: fipId, authorName: authorName, type: type, content: content, ts: now, expiresAt: now + 24 * 60 * 60 * 1000);
    final stories = await LocalStore.loadStories();
    stories.add(story.toJson());
    await LocalStore.saveStories(stories);
    await PhotonApi.postStory(serverUrl, fipId, story.toJson());
  }

  static Future<List<StoryItem>> loadStories() async {
    final raw = await LocalStore.loadStories();
    return raw.map((j) => StoryItem.fromJson(j)).where((s) => !s.isExpired).toList();
  }

  static Future<List<StoryItem>> loadMyStories(String myFipId) async {
    final all = await loadStories();
    return all.where((s) => s.authorFipId == myFipId).toList();
  }

  static Future<void> deleteStory(String serverUrl, String fipId, String storyId) async {
    final stories = await LocalStore.loadStories();
    stories.removeWhere((s) => s['id'] == storyId);
    await LocalStore.saveStories(stories);
    await PhotonApi.deleteStory(serverUrl, fipId, storyId);
  }

  static Future<List<StoryItem>> loadContactStories(String serverUrl, String contactFipId) async {
    final raw = await PhotonApi.getStories(serverUrl, contactFipId);
    final now = DateTime.now().millisecondsSinceEpoch;
    return raw.map((j) => StoryItem.fromJson(j)).where((s) => s.expiresAt > now).toList();
  }
}
