import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUserName;
  final String otherUserUid;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserName,
    required this.otherUserUid,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _currentUser = FirebaseAuth.instance.currentUser!;

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();

    final db = FirebaseFirestore.instance;
    final now = FieldValue.serverTimestamp();

    // إضافة الرسالة
    await db
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .add({
      'text': text,
      'senderUid': _currentUser.uid,
      'senderName': _currentUser.displayName ?? 'أنا',
      'createdAt': now,
    });

    // تحديث آخر رسالة في المحادثة
    await db.collection('chats').doc(widget.chatId).update({
      'lastMessage': text,
      'lastMessageTime': now,
    });

    // التمرير للأسفل
    await Future.delayed(const Duration(milliseconds: 100));
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white24,
              child: Text(
                widget.otherUserName.substring(0, 1).toUpperCase(),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(width: 10),
            Text(widget.otherUserName,
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: Column(
        children: [
          // قائمة الرسائل
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('createdAt', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data?.docs ?? [];

                if (messages.isEmpty) {
                  return Center(
                    child: Text('ابدأ المحادثة!',
                        style: GoogleFonts.cairo(color: Colors.grey)),
                  );
                }

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg =
                        messages[index].data() as Map<String, dynamic>;
                    final isMe = msg['senderUid'] == _currentUser.uid;
                    return _buildMessageBubble(msg, isMe);
                  },
                );
              },
            ),
          ),

          // حقل الإرسال
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2))
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    textDirection: TextDirection.rtl,
                    style: GoogleFonts.cairo(),
                    decoration: InputDecoration(
                      hintText: 'اكتب رسالة...',
                      hintStyle: GoogleFonts.cairo(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFFF5F5FF),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                    maxLines: null,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF6C63FF),
                    ),
                    child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isMe) {
    final time = (msg['createdAt'] as Timestamp?)?.toDate();

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF6C63FF) : Colors.grey.shade100,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              msg['text'] ?? '',
              style: GoogleFonts.cairo(
                  color: isMe ? Colors.white : Colors.black87,
                  fontSize: 15),
              textDirection: TextDirection.rtl,
            ),
            if (time != null) ...[
              const SizedBox(height: 4),
              Text(
                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                style: GoogleFonts.cairo(
                  fontSize: 10,
                  color: isMe ? Colors.white70 : Colors.grey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
