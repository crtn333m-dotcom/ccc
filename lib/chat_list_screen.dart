import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  Future<void> _startNewChat(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final currentUser = FirebaseAuth.instance.currentUser!;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('محادثة جديدة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameCtrl,
          textDirection: TextDirection.rtl,
          style: GoogleFonts.cairo(),
          decoration: InputDecoration(
            hintText: 'ابحث بالاسم...',
            hintStyle: GoogleFonts.cairo(),
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;

              // البحث بالاسم في Firestore
              final query = await FirebaseFirestore.instance
                  .collection('users')
                  .where('name', isGreaterThanOrEqualTo: name)
                  .where('name', isLessThanOrEqualTo: '$name\uf8ff')
                  .get();

              final results = query.docs
                  .where((d) => d['uid'] != currentUser.uid)
                  .toList();

              if (!ctx.mounted) return;
              Navigator.pop(ctx);

              if (results.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('لم يُعثر على مستخدم بهذا الاسم',
                        style: GoogleFonts.cairo()),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              // إذا وجد أكثر من نتيجة، اعرضهم للاختيار
              if (results.length == 1) {
                _openOrCreateChat(context, currentUser, results.first.data());
              } else {
                _showUserPicker(context, currentUser, results);
              }
            },
            child: Text('بحث', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  void _showUserPicker(BuildContext context, User currentUser,
      List<QueryDocumentSnapshot> results) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('اختر المستخدم',
                style: GoogleFonts.cairo(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ...results.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF6C63FF),
                child: Text(
                  (data['name'] as String).substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(data['name'], style: GoogleFonts.cairo()),
              subtitle: Text(data['email'], style: GoogleFonts.cairo(fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _openOrCreateChat(context, currentUser, data);
              },
            );
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _openOrCreateChat(BuildContext context, User currentUser,
      Map<String, dynamic> otherUser) async {
    final db = FirebaseFirestore.instance;
    final myUid = currentUser.uid;
    final otherUid = otherUser['uid'] as String;

    // البحث عن محادثة موجودة بين المستخدمين
    final existing = await db
        .collection('chats')
        .where('participants', arrayContains: myUid)
        .get();

    String? chatId;
    for (final doc in existing.docs) {
      final parts = List<String>.from(doc['participants']);
      if (parts.contains(otherUid) && parts.length == 2) {
        chatId = doc.id;
        break;
      }
    }

    // إنشاء محادثة جديدة إذا لم توجد
    if (chatId == null) {
      final ref = await db.collection('chats').add({
        'participants': [myUid, otherUid],
        'participantNames': {
          myUid: currentUser.displayName ?? 'أنا',
          otherUid: otherUser['name'],
        },
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      chatId = ref.id;
    }

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: chatId!,
          otherUserName: otherUser['name'],
          otherUserUid: otherUid,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        title: Text('المحادثات',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
            tooltip: 'تسجيل الخروج',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: currentUser.uid)
            .orderBy('lastMessageTime', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final chats = snapshot.data?.docs ?? [];

          if (chats.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.chat_bubble_outline,
                      size: 80, color: Color(0xFFD0CEFF)),
                  const SizedBox(height: 16),
                  Text('لا توجد محادثات بعد',
                      style: GoogleFonts.cairo(
                          fontSize: 18, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text('ابدأ محادثة جديدة بالضغط على +',
                      style: GoogleFonts.cairo(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.separated(
            itemCount: chats.length,
            separatorBuilder: (, _) =>
                const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final chat = chats[index].data() as Map<String, dynamic>;
              final chatId = chats[index].id;
              final names = Map<String, dynamic>.from(
                  chat['participantNames'] ?? {});
              final otherUid = (chat['participants'] as List)
                  .firstWhere((uid) => uid != currentUser.uid);
              final otherName = names[otherUid] ?? 'مستخدم';
              final lastMsg = chat['lastMessage'] ?? '';
              final time = chat['lastMessageTime'] as Timestamp?;

              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(
                  radius: 26,
                  backgroundColor: const Color(0xFF6C63FF),
                  child: Text(
                    otherName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(otherName,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  lastMsg.isEmpty ? 'ابدأ المحادثة...' : lastMsg,
                  style: GoogleFonts.cairo(
                      color: Colors.grey, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: time != null
                    ? Text(
                        _formatTime(time.toDate()),
                        style: GoogleFonts.cairo(
                            fontSize: 11, color: Colors.grey),
                      )
                    : null,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      chatId: chatId,
                      otherUserName: otherName,
                      otherUserUid: otherUid,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _startNewChat(context),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        child: const Icon(Icons.edit),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}/${dt.month}';
  }
}
