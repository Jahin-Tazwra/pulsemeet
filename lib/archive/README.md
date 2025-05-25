# Archived Chat System Components

This directory contains the archived components from the previous chat system implementation that was replaced with the unified messaging interface.

## Archived Files

### Services
- `chat_service.dart` - Original pulse chat service
- `direct_message_service.dart` - Original direct message service

### Screens
- `pulse_chat_screen.dart` - Original pulse chat interface
- `direct_message_screen.dart` - Original direct message interface
- `chat_tab.dart` - Original chat tab with separate pulse/DM tabs

### Models
- `chat_message.dart` - Original chat message model (replaced with unified Message model)

### Widgets
- Various chat-related widgets that were specific to the old system

## Migration Notes

The new unified chat system provides:
- Single conversation interface for both pulse groups and direct messages
- Improved performance with better caching and real-time updates
- Enhanced encryption with Signal Protocol implementation
- Modern UI/UX following Material Design 3 principles
- Voice and video calling capabilities
- Advanced features like message scheduling and disappearing messages

## Database Schema Changes

The old schema with separate `chat_messages` and `direct_messages` tables has been replaced with:
- `conversations` table (unified conversation management)
- `messages` table (unified message storage)
- `conversation_participants` table (group membership management)
- Enhanced encryption key management tables

## Archived Date
{current_date}

## Reason for Archive
Complete system redesign for unified messaging interface with enhanced features and performance.
