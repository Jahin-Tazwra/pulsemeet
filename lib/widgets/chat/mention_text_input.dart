import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/services/pulse_participant_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A text input widget that supports @mentions
class MentionTextInput extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String pulseId;
  final Function(bool) onComposingChanged;
  final InputDecoration? decoration;
  final TextCapitalization textCapitalization;
  final int? maxLines;
  final int? minLines;

  const MentionTextInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.pulseId,
    required this.onComposingChanged,
    this.decoration,
    this.textCapitalization = TextCapitalization.sentences,
    this.maxLines,
    this.minLines,
  });

  @override
  State<MentionTextInput> createState() => _MentionTextInputState();
}

class _MentionTextInputState extends State<MentionTextInput> {
  final PulseParticipantService _participantService = PulseParticipantService();
  List<Profile> _participants = [];
  List<Profile> _filteredParticipants = [];
  bool _showMentionSuggestions = false;
  int _mentionStartIndex = -1;
  String _mentionQuery = '';
  Timer? _typingTimer;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _loadParticipants();
    _setupTextListener();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    super.dispose();
  }

  /// Load participants for the pulse
  Future<void> _loadParticipants() async {
    final participants =
        await _participantService.getParticipants(widget.pulseId);
    setState(() {
      _participants = participants;
    });
  }

  /// Setup text change listener
  void _setupTextListener() {
    widget.controller.addListener(() {
      // Check for mention
      _checkForMention();

      // Update composing state
      final isComposing = widget.controller.text.trim().isNotEmpty;
      widget.onComposingChanged(isComposing);

      // Update typing status
      _updateTypingStatus(isComposing);
    });
  }

  /// Update typing status with debounce
  void _updateTypingStatus(bool isComposing) {
    // Cancel existing timer
    _typingTimer?.cancel();

    // Set typing status if changed
    if (isComposing != _isTyping) {
      _isTyping = isComposing;
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        _participantService.setTypingStatus(
            widget.pulseId, userId, isComposing);
      }
    }

    // If still typing, set a timer to clear typing status after 5 seconds of inactivity
    if (isComposing) {
      _typingTimer = Timer(const Duration(seconds: 5), () {
        if (_isTyping) {
          _isTyping = false;
          final userId = Supabase.instance.client.auth.currentUser?.id;
          if (userId != null) {
            _participantService.setTypingStatus(widget.pulseId, userId, false);
          }
        }
      });
    }
  }

  /// Check for mention in text
  void _checkForMention() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;

    // Only check if we have a valid selection
    if (!selection.isValid) return;

    // Find the last @ symbol before the cursor
    int atIndex = -1;
    for (int i = selection.start - 1; i >= 0; i--) {
      if (text[i] == '@') {
        atIndex = i;
        break;
      } else if (text[i] == ' ' || text[i] == '\n') {
        // Stop at whitespace
        break;
      }
    }

    if (atIndex >= 0) {
      // Extract the mention query
      final query = text.substring(atIndex + 1, selection.start).toLowerCase();

      // Filter participants
      final filtered = _participants.where((p) {
        final username = p.username?.toLowerCase() ?? '';
        final displayName = p.displayName?.toLowerCase() ?? '';
        return username.contains(query) || displayName.contains(query);
      }).toList();

      // Update state with filtered participants and query
      setState(() {
        _showMentionSuggestions = filtered.isNotEmpty;
        _filteredParticipants = filtered;
        _mentionStartIndex = atIndex;
        _mentionQuery = query; // Store query for potential future use
      });
    } else {
      setState(() {
        _showMentionSuggestions = false;
        _mentionStartIndex = -1;
        _mentionQuery = '';
      });
    }
  }

  /// Insert a mention at the current position
  void _insertMention(Profile profile) {
    if (_mentionStartIndex < 0) return;

    final text = widget.controller.text;
    final username = profile.username ?? profile.id;

    // Replace the @query with @username
    final newText = text.replaceRange(
        _mentionStartIndex, widget.controller.selection.start, '@$username ');

    // Update the text and selection
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: _mentionStartIndex + username.length + 2, // +2 for @ and space
      ),
    );

    // Hide suggestions
    setState(() {
      _showMentionSuggestions = false;
      _mentionStartIndex = -1;
      _mentionQuery = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mention suggestions
        if (_showMentionSuggestions)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color:
                      Colors.black.withAlpha(26), // Equivalent to opacity 0.1
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _filteredParticipants.length,
              itemBuilder: (context, index) {
                final participant = _filteredParticipants[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: participant.avatarUrl != null
                        ? NetworkImage(participant.avatarUrl!)
                        : null,
                    child: participant.avatarUrl == null
                        ? Text(participant.displayName?[0] ??
                            participant.username?[0] ??
                            '?')
                        : null,
                  ),
                  title: Text(participant.displayName ??
                      participant.username ??
                      'Unknown'),
                  subtitle: participant.username != null
                      ? Text('@${participant.username}')
                      : null,
                  dense: true,
                  onTap: () => _insertMention(participant),
                );
              },
            ),
          ),

        // Text field
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          decoration: widget.decoration,
          textCapitalization: widget.textCapitalization,
          maxLines: widget.maxLines,
          minLines: widget.minLines,
        ),
      ],
    );
  }
}
