import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/haptics.dart';
import 'glass_container.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderName,
    required this.text,
    required this.timestamp,
    required this.isMe,
  });

  final String id;
  final String senderName;
  final String text;
  final String timestamp;
  final bool isMe;
}

/// Opens the Live Journey Co-Passenger Chat room sheet (verification bypassed for testing).
Future<void> showJourneyChatSheet(
  BuildContext context, {
  required String trainNumber,
  required String trainName,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.60),
    builder: (ctx) => _JourneyChatSheetContent(
      trainNumber: trainNumber,
      trainName: trainName,
    ),
  );
}

class _JourneyChatSheetContent extends StatefulWidget {
  const _JourneyChatSheetContent({
    required this.trainNumber,
    required this.trainName,
  });

  final String trainNumber;
  final String trainName;

  @override
  State<_JourneyChatSheetContent> createState() => _JourneyChatSheetContentState();
}

class _JourneyChatSheetContentState extends State<_JourneyChatSheetContent> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isFullScreen = false;

  final List<ChatMessage> _messages = [];

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    Haptics.confirm();
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    setState(() {
      _messages.add(
        ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          senderName: 'You (Me)',
          text: text,
          timestamp: timeStr,
          isMe: true,
        ),
      );
      _inputController.clear();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final sheetHeight =
        MediaQuery.of(context).size.height * (_isFullScreen ? 0.92 : 0.72);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      padding: EdgeInsets.only(
        left: _isFullScreen ? 4 : 12,
        right: _isFullScreen ? 4 : 12,
        top: _isFullScreen ? 4 : 12,
        bottom: 12 + bottomInset,
      ),
      child: GlassContainer(
        radius: _isFullScreen ? 20 : 28,
        blurSigma: 24,
        strong: true,
        glow: true,
        padding: const EdgeInsets.all(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          height: sheetHeight,
          child: Column(
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: GlassTheme.accentViolet.withValues(alpha: 0.20),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.forum_rounded,
                      size: 22,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.trainNumber} ${widget.trainName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.titleStrong.copyWith(
                            color: g.textPrimary,
                            fontSize: 16.5,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFF34C759),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '18 Co-passengers online · Live Chat',
                              style: AppText.label.copyWith(
                                color: g.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Haptics.tap();
                      setState(() => _isFullScreen = !_isFullScreen);
                    },
                    icon: Icon(
                      _isFullScreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      color: g.textMuted,
                      size: 22,
                    ),
                    tooltip: _isFullScreen ? 'Exit Fullscreen' : 'Fullscreen',
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: g.textMuted),
                  ),
                ],
              ),
              const Divider(height: 20, color: Colors.white10),

              // Messages list
              Expanded(
                child: _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 40,
                              color: g.textMuted.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No messages yet',
                              style: AppText.titleStrong.copyWith(
                                color: g.textPrimary,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Be the first to send a message to co-passengers!',
                              style: AppText.label.copyWith(
                                color: g.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ScrollConfiguration(
                        behavior:
                            ScrollConfiguration.of(context).copyWith(scrollbars: false),
                        child: ListView.builder(
                          controller: _scrollController,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _messages.length,
                          itemBuilder: (ctx, idx) {
                            final msg = _messages[idx];
                            return _buildMessageBubble(ctx, msg);
                          },
                        ),
                      ),
              ),

              const SizedBox(height: 10),

              // Input bar
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: g.isDark
                            ? g.fill.withValues(alpha: 0.40)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: g.border.withValues(alpha: 0.30),
                        ),
                      ),
                      child: TextField(
                        controller: _inputController,
                        style: TextStyle(color: g.textPrimary, fontSize: 14),
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: 'Type a message to co-passengers…',
                          hintStyle:
                              TextStyle(color: g.textMuted, fontSize: 13.5),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: GlassTheme.accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: GlassTheme.accentIndigo
                                .withValues(alpha: 0.40),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.send_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessage msg) {
    final g = context.glass;
    final isDark = g.isDark;

    final senderColor = msg.isMe
        ? Colors.white.withValues(alpha: 0.90)
        : (isDark ? const Color(0xFFA78BFA) : const Color(0xFF6D28D9));

    final bubbleBg = msg.isMe
        ? null
        : (isDark
            ? g.fill.withValues(alpha: 0.45)
            : const Color(0xFFE2E8F0));

    final textColor = msg.isMe
        ? Colors.white
        : (isDark ? g.textPrimary : const Color(0xFF0F172A));

    final timestampColor = msg.isMe
        ? Colors.white.withValues(alpha: 0.70)
        : (isDark ? g.textMuted : const Color(0xFF64748B));

    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: msg.isMe ? GlassTheme.accent : null,
          color: bubbleBg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.isMe ? 16 : 4),
            bottomRight: Radius.circular(msg.isMe ? 4 : 16),
          ),
          border: Border.all(
            color: msg.isMe
                ? Colors.transparent
                : g.border.withValues(alpha: 0.30),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              msg.senderName,
              style: TextStyle(
                color: senderColor,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              msg.text,
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              msg.timestamp,
              style: TextStyle(
                color: timestampColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.1, end: 0),
    );
  }
}
