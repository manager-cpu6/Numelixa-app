import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../core/theme/app_theme.dart';
import '../services/api_client.dart';

class HelpTeamScreen extends StatefulWidget {
  const HelpTeamScreen({super.key, required this.accessToken});

  final String? accessToken;

  @override
  State<HelpTeamScreen> createState() => _HelpTeamScreenState();
}

class _HelpTeamScreenState extends State<HelpTeamScreen> {
  final ApiClient api = ApiClient();
  final TextEditingController text = TextEditingController();
  final ScrollController scroll = ScrollController();
  final AudioRecorder recorder = AudioRecorder();
  final ImagePicker picker = ImagePicker();
  final AudioPlayer player = AudioPlayer();

  final List<Map<String, dynamic>> messages = [];
  Timer? poll;
  bool loading = true;
  bool sending = false;
  bool recording = false;
  String? error;
  int? rating;
  String? reaction;

  @override
  void initState() {
    super.initState();
    load();
    poll = Timer.periodic(const Duration(seconds: 5), (_) => load(silent: true));
  }

  @override
  void dispose() {
    poll?.cancel();
    text.dispose();
    scroll.dispose();
    recorder.dispose();
    player.dispose();
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent && mounted) setState(() => loading = true);
    try {
      final d = await api.get('/api/support/chat', accessToken: widget.accessToken);
      final conversation = d['conversation'];
      final rows = (d['messages'] as List? ?? const [])
          .whereType<Map>()
          .map((x) => Map<String, dynamic>.from(x))
          .toList();
      if (mounted) {
        setState(() {
          messages
            ..clear()
            ..addAll(rows);
          error = null;
          loading = false;
          if (conversation is Map) {
            rating = conversation['rating'] is num ? (conversation['rating'] as num).toInt() : null;
            reaction = conversation['reaction']?.toString();
          }
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Future<void> send({List<Map<String, dynamic>> attachments = const []}) async {
    final value = text.text.trim();
    if ((value.isEmpty && attachments.isEmpty) || sending) return;
    if (mounted) setState(() => sending = true);
    try {
      final d = await api.post(
        '/api/support/chat',
        accessToken: widget.accessToken,
        body: {'text': value, 'attachments': attachments},
      );
      if (d['message'] is Map) {
        if (mounted) {
          setState(() => messages.add(Map<String, dynamic>.from(d['message'])));
          text.clear();
        }
      }
      await load(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> imageMessage() async {
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 1400,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (bytes.length > 3 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choose an image under 3 MB.')),
        );
      }
      return;
    }
    final mime = x.mimeType ?? 'image/jpeg';
    await send(attachments: [
      {
        'name': x.name,
        'mime': mime,
        'kind': 'image',
        'data': 'data:$mime;base64,${base64Encode(bytes)}',
      },
    ]);
  }

  Future<void> videoMessage() async {
    final x = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 1));
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (bytes.length > 3 * 1024 * 1024) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a video smaller than 3 MB.')),
      );
      return;
    }
    final mime = x.mimeType ?? 'video/mp4';
    await send(attachments: [{
      'name': x.name, 'mime': mime, 'kind': 'video',
      'data': 'data:$mime;base64,${base64Encode(bytes)}',
    }]);
  }

  Future<void> rateChat(int stars, String vote) async {
    try {
      await api.post('/api/support/chat', accessToken: widget.accessToken,
          body: {'action': 'rate', 'rating': stars, 'reaction': vote});
      if (mounted) setState(() { rating = stars; reaction = vote; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thank you for rating Help Team.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> deleteVoice(Map<String, dynamic> message) async {
    try {
      await api.delete('/api/support/chat?messageId=${Uri.encodeQueryComponent((message['id'] ?? '').toString())}', accessToken: widget.accessToken);
      if (mounted) setState(() => messages.removeWhere((m) => m['id'] == message['id']));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> voiceMessage() async {
    if (recording) {
      final path = await recorder.stop();
      if (mounted) setState(() => recording = false);
      if (path == null) return;
      final bytes = await File(path).readAsBytes();
      if (bytes.length > 3 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Voice note is too large; record a shorter one.')),
          );
        }
        return;
      }
      await send(attachments: [
        {
          'name': 'voice-message.m4a',
          'mime': 'audio/mp4',
          'kind': 'audio',
          'data': 'data:audio/mp4;base64,${base64Encode(bytes)}',
        },
      ]);
      return;
    }

    if (!await recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required.')),
        );
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/numelixa-voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
    await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    if (mounted) setState(() => recording = true);
  }

  Future<void> playVoice(String data) async {
    try {
      await player.play(BytesSource(base64Decode(data.split(',').last)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not play this voice note.')),
        );
      }
    }
  }

  Widget _attachmentWidget(Map<String, dynamic> a, Map<String, dynamic> message) {
    final kind = (a['kind'] ?? '').toString();
    final data = (a['data'] ?? '').toString();
    if (kind == 'image' && data.contains(',')) {
      try {
        final bytes = base64Decode(data.split(',').last);
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: GestureDetector(
            onTap: () => showDialog<void>(context: context, barrierColor: Colors.black.withOpacity(.96),
              builder: (_) => Dialog.fullscreen(backgroundColor: Colors.black,
                child: Stack(children: [
                  Center(child: InteractiveViewer(minScale: .5, maxScale: 6,
                    child: Image.memory(bytes, fit: BoxFit.contain))),
                  Positioned(top: 18, right: 18, child: IconButton.filled(
                    onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))),
                ]))),
            child: ClipRRect(borderRadius: BorderRadius.circular(10),
              child: Image.memory(bytes, width: 240, fit: BoxFit.contain)),
          ),
        );
      } catch (_) { return const SizedBox.shrink(); }
    }
    if (kind == 'audio' && data.contains(',')) {
      return Wrap(spacing: 6, children: [
        TextButton.icon(onPressed: () => playVoice(data),
          icon: const Icon(Icons.play_circle, color: AppTheme.cyan), label: const Text('Play voice')),
        TextButton.icon(onPressed: () => deleteVoice(message),
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent), label: const Text('Delete')),
      ]);
    }
    if (kind == 'video' && data.contains(',')) return _UserChatVideo(dataUrl: data);
    return Text('Attachment: ${a['name'] ?? 'file'}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff030817),
      appBar: AppBar(
        backgroundColor: const Color(0xff071329),
        title: const Row(
          children: [
            Icon(Icons.support_agent_rounded, color: AppTheme.cyan),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Help Team', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text('Private support chat', style: TextStyle(fontSize: 11, color: AppTheme.cyan)),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xff102d4d), Color(0xff151c3b)],
              ),
              border: Border.all(color: AppTheme.cyan.withOpacity(.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.verified_user_outlined, color: AppTheme.cyan, size: 32),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Numelixa Support', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 3),
                      Text(
                        'Send a message, image or voice note. Only you and the Help Team can see this chat.',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(error!, style: const TextStyle(color: Colors.orangeAccent)),
            ),
          Expanded(
            child: loading && messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.forum_outlined, size: 48, color: AppTheme.cyan),
                            SizedBox(height: 10),
                            Text('Start a conversation',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            Text('The Help Team is here to help.',
                                style: TextStyle(color: Colors.white60)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.all(12),
                        itemCount: messages.length,
                        itemBuilder: (context, i) {
                          final m = messages[i];
                          final mine = m['senderRole'] != 'admin';
                          final attachments = (m['attachments'] as List? ?? const []);
                          return Align(
                            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 320),
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: mine ? const Color(0xff123c55) : const Color(0xff1c2540),
                                borderRadius: BorderRadius.circular(17),
                                border: Border.all(color: AppTheme.cyan.withOpacity(.18)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    mine ? 'You' : 'Numelixa Help Team',
                                    style: const TextStyle(
                                      color: AppTheme.cyan,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                  if ((m['text'] ?? '').toString().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 5),
                                      child: Text(
                                        m['text'].toString(),
                                        style: const TextStyle(height: 1.35),
                                      ),
                                    ),
                                  ...attachments.whereType<Map>().map((a) => _attachmentWidget(Map<String, dynamic>.from(a), m)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (messages.isNotEmpty)
            Padding(padding: const EdgeInsets.fromLTRB(10, 4, 10, 4), child: Wrap(alignment: WrapAlignment.center, spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('Rate support', style: TextStyle(color: Colors.white60, fontSize: 11)),
              for (var star = 1; star <= 5; star++) IconButton(visualDensity: VisualDensity.compact, constraints: const BoxConstraints(minWidth: 30, minHeight: 30), padding: EdgeInsets.zero, onPressed: () => rateChat(star, reaction ?? 'like'), icon: Icon(star <= (rating ?? 0) ? Icons.star_rounded : Icons.star_outline_rounded, size: 20, color: Colors.amber)),
              IconButton(visualDensity: VisualDensity.compact, onPressed: () => rateChat(rating ?? 5, 'like'), icon: Icon(Icons.thumb_up_alt_outlined, size: 19, color: reaction == 'like' ? AppTheme.cyan : Colors.white54)),
              IconButton(visualDensity: VisualDensity.compact, onPressed: () => rateChat(rating ?? 1, 'dislike'), icon: Icon(Icons.thumb_down_alt_outlined, size: 19, color: reaction == 'dislike' ? Colors.redAccent : Colors.white54)),
            ])),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xff1b3048))),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: sending ? null : imageMessage,
                    tooltip: 'Attach image',
                    icon: const Icon(Icons.image_outlined, color: AppTheme.cyan),
                  ),
                  IconButton(
                    onPressed: sending ? null : videoMessage,
                    tooltip: 'Attach video',
                    icon: const Icon(Icons.video_library_outlined, color: AppTheme.cyan),
                  ),
                  IconButton(
                    onPressed: sending ? null : voiceMessage,
                    tooltip: recording ? 'Stop recording' : 'Record voice',
                    icon: Icon(
                      recording ? Icons.stop_circle : Icons.mic_none,
                      color: recording ? Colors.redAccent : AppTheme.cyan,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: text,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: recording ? 'Recording voice note…' : 'Message Help Team',
                        filled: true,
                        fillColor: const Color(0xff111d33),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onSubmitted: (_) => send(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  CircleAvatar(
                    backgroundColor: AppTheme.cyan,
                    child: IconButton(
                      onPressed: sending ? null : () => send(),
                      icon: sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.black),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserChatVideo extends StatefulWidget {
  const _UserChatVideo({required this.dataUrl});
  final String dataUrl;
  @override
  State<_UserChatVideo> createState() => _UserChatVideoState();
}
class _UserChatVideoState extends State<_UserChatVideo> {
  VideoPlayerController? controller;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/numelixa-chat-video-${DateTime.now().microsecondsSinceEpoch}.mp4');
      await file.writeAsBytes(base64Decode(widget.dataUrl.split(',').last), flush: true);
      final value = VideoPlayerController.file(file);
      await value.initialize();
      if (!mounted) { await value.dispose(); return; }
      setState(() => controller = value);
    } catch (_) {}
  }
  @override
  void dispose() { controller?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final value = controller;
    if (value == null || !value.value.isInitialized) {
      return const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return SizedBox(width: 260, child: Column(children: [
      AspectRatio(aspectRatio: value.value.aspectRatio, child: VideoPlayer(value)),
      IconButton(onPressed: () => setState(() => value.value.isPlaying ? value.pause() : value.play()),
        icon: Icon(value.value.isPlaying ? Icons.pause_circle : Icons.play_circle, color: AppTheme.cyan, size: 32)),
    ]));
  }
}
