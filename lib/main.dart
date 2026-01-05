import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const NoticeApp());
}

enum UserRole { admin, executive, member }

enum NoticeCategory { notice, decision, event }

enum Audience { all, executivesOnly }

enum OpinionCategory { workplace, workingHours, harassment }

class UserProfile {
  UserProfile({
    required this.uid,
    required this.groupId,
    required this.groupName,
    required this.nickname,
    required this.role,
    required this.loginId,
    required this.email,
  });

  final String uid;
  final String groupId;
  final String groupName;
  final String nickname;
  final UserRole role;
  final String loginId;
  final String email;

  factory UserProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('User profile missing.');
    }
    return UserProfile(
      uid: doc.id,
      groupId: data['groupId'] as String? ?? 'default',
      groupName: data['groupName'] as String? ?? '団体',
      nickname: data['nickname'] as String? ?? 'ニックネーム',
      role: _roleFromString(data['role'] as String? ?? 'member'),
      loginId: data['loginId'] as String? ?? '',
      email: data['email'] as String? ?? '',
    );
  }
}

class Announcement {
  Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.audience,
    required this.photoCount,
    required this.readRate,
    required this.likes,
  });

  final String id;
  final String title;
  final String body;
  final NoticeCategory category;
  final Audience audience;
  final int photoCount;
  final int readRate;
  final int likes;

  factory Announcement.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Announcement(
      id: doc.id,
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      category: _noticeFromString(data['category'] as String? ?? 'notice'),
      audience: _audienceFromString(data['audience'] as String? ?? 'all'),
      photoCount: data['photoCount'] as int? ?? 0,
      readRate: data['readRate'] as int? ?? 0,
      likes: data['likes'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap({required String creatorUid}) {
    return {
      'title': title,
      'body': body,
      'category': _noticeToString(category),
      'audience': _audienceToString(audience),
      'photoCount': photoCount,
      'readRate': readRate,
      'likes': likes,
      'creatorUid': creatorUid,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

class DecisionItem {
  DecisionItem({
    required this.content,
    required this.owner,
    this.deadline,
    this.isDone = false,
  });

  final String content;
  final String owner;
  final String? deadline;
  final bool isDone;

  factory DecisionItem.fromMap(Map<String, dynamic> data) {
    return DecisionItem(
      content: data['content'] as String? ?? '',
      owner: data['owner'] as String? ?? '',
      deadline: data['deadline'] as String?,
      isDone: data['isDone'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'content': content,
      'owner': owner,
      'deadline': deadline,
      'isDone': isDone,
    };
  }
}

class DecisionMeeting {
  DecisionMeeting({
    required this.id,
    required this.date,
    required this.items,
  });

  final String id;
  final DateTime date;
  final List<DecisionItem> items;

  factory DecisionMeeting.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final timestamp = data['date'] as Timestamp?;
    final itemsRaw = data['items'] as List<dynamic>? ?? [];
    return DecisionMeeting(
      id: doc.id,
      date: timestamp?.toDate() ?? DateTime.now(),
      items: itemsRaw
          .whereType<Map<String, dynamic>>()
          .map(DecisionItem.fromMap)
          .toList(),
    );
  }
}

class Opinion {
  Opinion({
    required this.id,
    required this.category,
    required this.text,
    required this.isPublicReply,
    this.reply,
  });

  final String id;
  final OpinionCategory category;
  final String text;
  final bool isPublicReply;
  final String? reply;

  factory Opinion.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Opinion(
      id: doc.id,
      category: _opinionFromString(data['category'] as String? ?? 'workplace'),
      text: data['text'] as String? ?? '',
      isPublicReply: data['isPublicReply'] as bool? ?? false,
      reply: data['reply'] as String?,
    );
  }

  Map<String, dynamic> toMap({required String creatorUid}) {
    return {
      'category': _opinionToString(category),
      'text': text,
      'isPublicReply': false,
      'reply': null,
      'creatorUid': creatorUid,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<Announcement>> watchAnnouncements(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(Announcement.fromDoc)
              .toList(growable: false),
        );
  }

  Future<void> addAnnouncement(
    String groupId,
    Announcement announcement,
    UserProfile profile,
  ) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('announcements')
        .add(announcement.toMap(creatorUid: profile.uid));
  }

  Future<void> incrementLike(String groupId, String announcementId) {
    final ref = _firestore
        .collection('groups')
        .doc(groupId)
        .collection('announcements')
        .doc(announcementId);
    return _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      final current = (snap.data()?['likes'] as int?) ?? 0;
      transaction.update(ref, {'likes': current + 1});
    });
  }

  Stream<List<DecisionMeeting>> watchMeetings(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('meetings')
        .orderBy('date', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(DecisionMeeting.fromDoc)
              .toList(growable: false),
        );
  }

  Future<void> addDecisionItem(
    String groupId,
    DecisionMeeting meeting,
    DecisionItem item,
  ) async {
    final ref = _firestore
        .collection('groups')
        .doc(groupId)
        .collection('meetings')
        .doc(meeting.id);
    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      final data = snap.data() ?? {};
      final rawItems = List<Map<String, dynamic>>.from(
        (data['items'] as List<dynamic>? ?? []),
      );
      if (rawItems.length >= 3) {
        throw StateError('1回の会議につき最大3件までです。');
      }
      rawItems.add(item.toMap());
      transaction.update(ref, {'items': rawItems});
    });
  }

  Future<void> toggleDecisionItemDone(
    String groupId,
    DecisionMeeting meeting,
    int itemIndex,
    bool value,
  ) async {
    final ref = _firestore
        .collection('groups')
        .doc(groupId)
        .collection('meetings')
        .doc(meeting.id);
    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      final data = snap.data() ?? {};
      final rawItems = List<Map<String, dynamic>>.from(
        (data['items'] as List<dynamic>? ?? []),
      );
      if (itemIndex < 0 || itemIndex >= rawItems.length) {
        return;
      }
      final updated = Map<String, dynamic>.from(rawItems[itemIndex]);
      updated['isDone'] = value;
      rawItems[itemIndex] = updated;
      transaction.update(ref, {'items': rawItems});
    });
  }

  Stream<List<Opinion>> watchOpinions(String groupId, {required bool forExecutive}) {
    var query = _firestore
        .collection('groups')
        .doc(groupId)
        .collection('opinions')
        .orderBy('createdAt', descending: true);
    if (!forExecutive) {
      query = query.where('isPublicReply', isEqualTo: true);
    }
    return query.snapshots().map(
          (snapshot) =>
              snapshot.docs.map(Opinion.fromDoc).toList(growable: false),
        );
  }

  Future<void> addOpinion(
    String groupId,
    Opinion opinion,
    UserProfile profile,
  ) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('opinions')
        .add(opinion.toMap(creatorUid: profile.uid));
  }

  Future<void> replyOpinion(
    String groupId,
    String opinionId,
    String reply,
    bool isPublic,
  ) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('opinions')
        .doc(opinionId)
        .update({'reply': reply, 'isPublicReply': isPublic});
  }
}

class NoticeApp extends StatelessWidget {
  const NoticeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF15616D)),
      scaffoldBackgroundColor: const Color(0xFFF7F5F0),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(fontSize: 16),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '組合お知らせ',
      theme: theme,
      home: const AppRoot(),
    );
  }
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScaffold(message: '認証を確認しています...');
        }
        final user = snapshot.data;
        if (user == null) {
          return const SignInPage();
        }
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingScaffold(message: 'プロフィールを読み込み中...');
            }
            if (!profileSnapshot.hasData ||
                !(profileSnapshot.data?.exists ?? false)) {
              return _ProfileMissingPage(onLogout: _signOut);
            }
            final profile =
                UserProfile.fromDoc(profileSnapshot.data!);
            return HomePage(profile: profile);
          },
        );
      },
    );
  }
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final TextEditingController _loginIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _loginIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final loginId = _loginIdController.text.trim();
    final password = _passwordController.text.trim();
    if (loginId.isEmpty || password.isEmpty) {
      _showSnack('ユーザーIDとパスワードを入力してください。');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final normalizedLoginId = loginId.toLowerCase();
      final lookupDoc = await FirebaseFirestore.instance
          .collection('login_lookup')
          .doc(normalizedLoginId)
          .get();
      if (!lookupDoc.exists) {
        _showSnack('ユーザーIDが見つかりませんでした。');
        return;
      }
      final data = lookupDoc.data();
      final email = data?['email'] as String?;
      if (email == null || email.isEmpty) {
        _showSnack('管理者にメール設定を依頼してください。');
        return;
      }
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      _showSnack(e.message ?? 'ログインに失敗しました。');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEDE6D7), Color(0xFFF7F5F0)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '既存アカウントでログイン',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                const Text('管理者から配布されたアカウントを使用します。'),
                const SizedBox(height: 24),
                _SectionCard(
                  title: 'ユーザーID',
                  child: TextField(
                    controller: _loginIdController,
                    decoration: const InputDecoration(
                      hintText: 'U-000123',
                      filled: true,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'パスワード',
                  child: TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      hintText: '********',
                      filled: true,
                    ),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _signIn,
                    child: Text(_isLoading ? '確認中...' : 'ログイン'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileMissingPage extends StatelessWidget {
  const _ProfileMissingPage({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('プロフィールが未登録です。',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text('管理者にユーザー登録を依頼してください。'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onLogout,
                child: const Text('ログアウト'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    );
  }
}

Future<void> _signOut() => FirebaseAuth.instance.signOut();

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  final FirestoreService _service = FirestoreService();

  @override
  Widget build(BuildContext context) {
    final pages = [
      TimelinePage(profile: widget.profile, service: _service),
      PostCreationPage(profile: widget.profile, service: _service),
      DecisionSummaryPage(profile: widget.profile, service: _service),
      OpinionBoxPage(profile: widget.profile, service: _service),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.profile.groupName} | ${_roleLabel(widget.profile.role)}'),
        actions: [
          IconButton(
            onPressed: _signOut,
            tooltip: 'ログアウト',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (value) => setState(() => _currentIndex = value),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.timeline), label: 'タイムライン'),
          BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '投稿作成'),
          BottomNavigationBarItem(icon: Icon(Icons.checklist), label: '決定事項'),
          BottomNavigationBarItem(
            icon: Icon(Icons.question_answer_outlined),
            label: '匿名意見',
          ),
        ],
      ),
    );
  }
}

class TimelinePage extends StatelessWidget {
  const TimelinePage({
    super.key,
    required this.profile,
    required this.service,
  });

  final UserProfile profile;
  final FirestoreService service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Announcement>>(
      stream: service.watchAnnouncements(profile.groupId),
      builder: (context, snapshot) {
        final announcements = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _InfoBanner(
              title: 'お知らせ一覧',
              subtitle: 'コメントは禁止。読むだけ・反応は👍のみ。',
            ),
            const SizedBox(height: 16),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(child: CircularProgressIndicator()),
            if (announcements.isEmpty &&
                snapshot.connectionState != ConnectionState.waiting)
              const _EmptyState(message: 'まだ投稿がありません。'),
            ...announcements.map((announcement) {
              final isRestricted =
                  announcement.audience == Audience.executivesOnly &&
                      profile.role == UserRole.member;
              if (isRestricted) {
                return const _MaskedCard(
                  title: '執行部向け投稿',
                  caption: '閲覧権限がありません。',
                );
              }
              return _AnnouncementCard(
                announcement: announcement,
                onLike: () =>
                    service.incrementLike(profile.groupId, announcement.id),
              );
            }),
          ],
        );
      },
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.announcement, required this.onLike});

  final Announcement announcement;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final categoryLabel = _categoryLabel(announcement.category);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _CategoryChip(label: categoryLabel),
                const SizedBox(width: 8),
                if (announcement.audience == Audience.executivesOnly)
                  const _CategoryChip(label: '執行部のみ', isAccent: true),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              announcement.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(announcement.body),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.photo, size: 18),
                const SizedBox(width: 6),
                Text('写真 ${announcement.photoCount}枚'),
                const Spacer(),
                const Icon(Icons.visibility, size: 18),
                const SizedBox(width: 6),
                Text('既読率 ${announcement.readRate}%'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onLike,
                  icon: const Icon(Icons.thumb_up_alt_outlined),
                  label: Text('👍 ${announcement.likes}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PostCreationPage extends StatefulWidget {
  const PostCreationPage({
    super.key,
    required this.profile,
    required this.service,
  });

  final UserProfile profile;
  final FirestoreService service;

  @override
  State<PostCreationPage> createState() => _PostCreationPageState();
}

class _PostCreationPageState extends State<PostCreationPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  NoticeCategory _category = NoticeCategory.notice;
  Audience _audience = Audience.all;
  int _photoCount = 1;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _showSnack('タイトルと本文は必須です。');
      return;
    }
    if (title.length > 20 || body.length > 300) {
      _showSnack('文字数制限を超えています。');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await widget.service.addAnnouncement(
        widget.profile.groupId,
        Announcement(
          id: '',
          title: title,
          body: body,
          category: _category,
          audience: _audience,
          photoCount: _photoCount,
          readRate: 0,
          likes: 0,
        ),
        widget.profile,
      );
      _titleController.clear();
      _bodyController.clear();
      _photoCount = 1;
      _audience = Audience.all;
      _category = NoticeCategory.notice;
      _showSnack('投稿を作成しました。');
      setState(() {});
    } on FirebaseException catch (e) {
      _showSnack(e.message ?? '投稿に失敗しました。');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.profile.role == UserRole.member) {
      return const _AccessLimitedView(
        title: '執行部のみ利用できます',
        message: '投稿作成は執行部・管理者のみ可能です。',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoBanner(
          title: 'お知らせ作成',
          subtitle: '長文禁止。タイトル20字、本文300字まで。',
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'タイトル（20字以内）',
          child: TextField(
            controller: _titleController,
            maxLength: 20,
            decoration: const InputDecoration(
              hintText: '例：秋の説明会',
              filled: true,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: '本文（300字以内）',
          child: TextField(
            controller: _bodyController,
            maxLength: 300,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: '短く要点だけ書いてください。',
              filled: true,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'カテゴリ',
          child: Wrap(
            spacing: 8,
            children: NoticeCategory.values.map((category) {
              return ChoiceChip(
                label: Text(_categoryLabel(category)),
                selected: _category == category,
                onSelected: (_) => setState(() => _category = category),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: '公開対象',
          child: Column(
            children: [
              RadioListTile<Audience>(
                value: Audience.all,
                groupValue: _audience,
                onChanged: (value) => setState(() => _audience = value!),
                title: const Text('全組合員'),
              ),
              RadioListTile<Audience>(
                value: Audience.executivesOnly,
                groupValue: _audience,
                onChanged: (value) => setState(() => _audience = value!),
                title: const Text('執行部のみ'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: '写真添付（1〜3枚）',
          child: Row(
            children: [
              IconButton(
                onPressed: _photoCount > 1
                    ? () => setState(() => _photoCount -= 1)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_photoCount 枚'),
              IconButton(
                onPressed: _photoCount < 3
                    ? () => setState(() => _photoCount += 1)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
              const SizedBox(width: 12),
              const Text('※仮の枚数設定'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: Text(_isSubmitting ? '送信中...' : '投稿を公開'),
          ),
        ),
      ],
    );
  }
}

class DecisionSummaryPage extends StatefulWidget {
  const DecisionSummaryPage({
    super.key,
    required this.profile,
    required this.service,
  });

  final UserProfile profile;
  final FirestoreService service;

  @override
  State<DecisionSummaryPage> createState() => _DecisionSummaryPageState();
}

class _DecisionSummaryPageState extends State<DecisionSummaryPage> {
  int _selectedMeeting = 0;
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _ownerController = TextEditingController();
  final TextEditingController _deadlineController = TextEditingController();
  bool _done = false;

  @override
  void dispose() {
    _contentController.dispose();
    _ownerController.dispose();
    _deadlineController.dispose();
    super.dispose();
  }

  Future<void> _addItem(List<DecisionMeeting> meetings) async {
    if (meetings.isEmpty) {
      _showSnack('会議データがありません。');
      return;
    }
    final content = _contentController.text.trim();
    final owner = _ownerController.text.trim();
    if (content.isEmpty || owner.isEmpty) {
      _showSnack('内容と担当は必須です。');
      return;
    }
    try {
      await widget.service.addDecisionItem(
        widget.profile.groupId,
        meetings[_selectedMeeting],
        DecisionItem(
          content: content,
          owner: owner,
          deadline:
              _deadlineController.text.trim().isEmpty
                  ? null
                  : _deadlineController.text.trim(),
          isDone: _done,
        ),
      );
      _contentController.clear();
      _ownerController.clear();
      _deadlineController.clear();
      _done = false;
      setState(() {});
      _showSnack('決定事項を追加しました。');
    } on StateError catch (e) {
      _showSnack(e.message);
    } on FirebaseException catch (e) {
      _showSnack(e.message ?? '追加に失敗しました。');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DecisionMeeting>>(
      stream: widget.service.watchMeetings(widget.profile.groupId),
      builder: (context, snapshot) {
        final meetings = snapshot.data ?? [];
        if (_selectedMeeting >= meetings.length) {
          _selectedMeeting = 0;
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _InfoBanner(
              title: '決定事項サマリー',
              subtitle: '1会議につき最大3件。議事録は作りません。',
            ),
            const SizedBox(height: 16),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(child: CircularProgressIndicator()),
            if (meetings.isEmpty &&
                snapshot.connectionState != ConnectionState.waiting)
              const _EmptyState(message: '決定事項がまだありません。'),
            if (meetings.isNotEmpty) ...[
              _SectionCard(
                title: '会議選択',
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: _selectedMeeting,
                  items: meetings.asMap().entries.map((entry) {
                    return DropdownMenuItem(
                      value: entry.key,
                      child: Text(_formatDate(entry.value.date)),
                    );
                  }).toList(),
                  onChanged: (value) =>
                      setState(() => _selectedMeeting = value ?? 0),
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: '決定事項を追加（執行部）',
                child: widget.profile.role == UserRole.member
                    ? const Text('執行部・管理者のみ追加できます。')
                    : Column(
                        children: [
                          TextField(
                            controller: _contentController,
                            decoration: const InputDecoration(
                              hintText: '内容',
                              filled: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _ownerController,
                            decoration: const InputDecoration(
                              hintText: '担当',
                              filled: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _deadlineController,
                            decoration: const InputDecoration(
                              hintText: '期限（任意）',
                              filled: true,
                            ),
                          ),
                          CheckboxListTile(
                            value: _done,
                            onChanged: (value) =>
                                setState(() => _done = value ?? false),
                            title: const Text('完了チェック'),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => _addItem(meetings),
                              child: const Text('追加'),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              ...meetings.asMap().entries.map((entry) {
                final meeting = entry.value;
                return _DecisionMeetingCard(
                  meeting: meeting,
                  meetingIndex: entry.key,
                  onToggle: (index, value) {
                    widget.service.toggleDecisionItemDone(
                      widget.profile.groupId,
                      meeting,
                      index,
                      value,
                    );
                  },
                );
              }),
            ],
          ],
        );
      },
    );
  }
}

class _DecisionMeetingCard extends StatelessWidget {
  const _DecisionMeetingCard({
    required this.meeting,
    required this.meetingIndex,
    required this.onToggle,
  });

  final DecisionMeeting meeting;
  final int meetingIndex;
  final void Function(int, bool) onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatDate(meeting.date),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            ...meeting.items.asMap().entries.map((entry) {
              final item = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EEE6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: item.isDone,
                      onChanged: (value) => onToggle(entry.key, value ?? false),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.content),
                          const SizedBox(height: 4),
                          Text('担当: ${item.owner}'),
                          if (item.deadline != null)
                            Text('期限: ${item.deadline}'),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class OpinionBoxPage extends StatefulWidget {
  const OpinionBoxPage({
    super.key,
    required this.profile,
    required this.service,
  });

  final UserProfile profile;
  final FirestoreService service;

  @override
  State<OpinionBoxPage> createState() => _OpinionBoxPageState();
}

class _OpinionBoxPageState extends State<OpinionBoxPage> {
  OpinionCategory _category = OpinionCategory.workplace;
  final TextEditingController _opinionController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _opinionController.dispose();
    super.dispose();
  }

  Future<void> _submitOpinion() async {
    final text = _opinionController.text.trim();
    if (text.isEmpty) {
      _showSnack('内容を入力してください。');
      return;
    }
    setState(() => _isSending = true);
    try {
      await widget.service.addOpinion(
        widget.profile.groupId,
        Opinion(
          id: '',
          category: _category,
          text: text,
          isPublicReply: false,
        ),
        widget.profile,
      );
      _opinionController.clear();
      _showSnack('匿名で送信しました。');
    } on FirebaseException catch (e) {
      _showSnack(e.message ?? '送信に失敗しました。');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isExecutive = widget.profile.role != UserRole.member;
    return StreamBuilder<List<Opinion>>(
      stream: widget.service.watchOpinions(
        widget.profile.groupId,
        forExecutive: isExecutive,
      ),
      builder: (context, snapshot) {
        final opinions = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _InfoBanner(
              title: '匿名意見・質問箱',
              subtitle: '個人特定につながる内容は書かないでください。',
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: '匿名投稿',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    children: OpinionCategory.values.map((category) {
                      return ChoiceChip(
                        label: Text(_opinionLabel(category)),
                        selected: _category == category,
                        onSelected: (_) =>
                            setState(() => _category = category),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  if (_category == OpinionCategory.harassment)
                    const Text(
                      '※ハラスメントは詳細を書かないでください。',
                      style: TextStyle(color: Color(0xFF8C1C13)),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _opinionController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: '短く要点だけ。匿名で送信されます。',
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSending ? null : _submitOpinion,
                      child: Text(_isSending ? '送信中...' : '匿名で送信'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(child: CircularProgressIndicator()),
            if (opinions.isEmpty &&
                snapshot.connectionState != ConnectionState.waiting)
              const _EmptyState(message: 'まだ意見がありません。'),
            if (!isExecutive) ...[
              _SectionCard(
                title: '公開返信',
                child: Column(
                  children: opinions
                      .map((opinion) => _PublicReplyTile(opinion: opinion))
                      .toList(),
                ),
              ),
            ] else ...[
              _SectionCard(
                title: '執行部のみ閲覧',
                child: Column(
                  children: opinions
                      .map(
                        (opinion) => _OpinionManageTile(
                          opinion: opinion,
                          onReply: (reply, isPublic) =>
                              widget.service.replyOpinion(
                            widget.profile.groupId,
                            opinion.id,
                            reply,
                            isPublic,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _OpinionManageTile extends StatelessWidget {
  const _OpinionManageTile({required this.opinion, required this.onReply});

  final Opinion opinion;
  final void Function(String, bool) onReply;

  void _openReplyDialog(BuildContext context) {
    final controller = TextEditingController(text: opinion.reply ?? '');
    bool isPublic = opinion.isPublicReply;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('返信'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    decoration: const InputDecoration(hintText: '返信内容'),
                  ),
                  SwitchListTile(
                    value: isPublic,
                    onChanged: (value) => setState(() => isPublic = value),
                    title: const Text('全体公開する'),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                onReply(controller.text.trim(), isPublic);
                Navigator.of(context).pop();
              },
              child: const Text('返信する'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(_opinionLabel(opinion.category)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Text(opinion.text),
            if (opinion.reply != null) ...[
              const SizedBox(height: 8),
              Text('返信: ${opinion.reply}'),
              Text(opinion.isPublicReply ? '公開中' : '非公開'),
            ],
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.reply),
          onPressed: () => _openReplyDialog(context),
        ),
      ),
    );
  }
}

class _PublicReplyTile extends StatelessWidget {
  const _PublicReplyTile({required this.opinion});

  final Opinion opinion;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(_opinionLabel(opinion.category)),
        subtitle: Text(opinion.reply ?? '返信準備中'),
      ),
    );
  }
}

class _AccessLimitedView extends StatelessWidget {
  const _AccessLimitedView({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE3DCCB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(subtitle),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, this.isAccent = false});

  final String label;
  final bool isAccent;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      backgroundColor: isAccent ? const Color(0xFFACC7B4) : null,
    );
  }
}

class _MaskedCard extends StatelessWidget {
  const _MaskedCard({required this.title, required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: const Icon(Icons.lock_outline),
        title: Text(title),
        subtitle: Text(caption),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(child: Text(message)),
    );
  }
}

String _categoryLabel(NoticeCategory category) {
  switch (category) {
    case NoticeCategory.notice:
      return 'お知らせ';
    case NoticeCategory.decision:
      return '決定事項';
    case NoticeCategory.event:
      return 'イベント';
  }
}

String _roleLabel(UserRole role) {
  switch (role) {
    case UserRole.admin:
      return '管理者';
    case UserRole.executive:
      return '執行部';
    case UserRole.member:
      return '一般組合員';
  }
}

String _opinionLabel(OpinionCategory category) {
  switch (category) {
    case OpinionCategory.workplace:
      return '職場環境';
    case OpinionCategory.workingHours:
      return '労働時間';
    case OpinionCategory.harassment:
      return 'ハラスメント';
  }
}

UserRole _roleFromString(String value) {
  switch (value) {
    case 'admin':
      return UserRole.admin;
    case 'executive':
      return UserRole.executive;
    default:
      return UserRole.member;
  }
}

NoticeCategory _noticeFromString(String value) {
  switch (value) {
    case 'decision':
      return NoticeCategory.decision;
    case 'event':
      return NoticeCategory.event;
    default:
      return NoticeCategory.notice;
  }
}

Audience _audienceFromString(String value) {
  switch (value) {
    case 'executivesOnly':
      return Audience.executivesOnly;
    default:
      return Audience.all;
  }
}

OpinionCategory _opinionFromString(String value) {
  switch (value) {
    case 'workingHours':
      return OpinionCategory.workingHours;
    case 'harassment':
      return OpinionCategory.harassment;
    default:
      return OpinionCategory.workplace;
  }
}

String _noticeToString(NoticeCategory category) {
  switch (category) {
    case NoticeCategory.notice:
      return 'notice';
    case NoticeCategory.decision:
      return 'decision';
    case NoticeCategory.event:
      return 'event';
  }
}

String _audienceToString(Audience audience) {
  switch (audience) {
    case Audience.executivesOnly:
      return 'executivesOnly';
    case Audience.all:
      return 'all';
  }
}

String _opinionToString(OpinionCategory category) {
  switch (category) {
    case OpinionCategory.workplace:
      return 'workplace';
    case OpinionCategory.workingHours:
      return 'workingHours';
    case OpinionCategory.harassment:
      return 'harassment';
  }
}

String _formatDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year/$month/$day';
}
