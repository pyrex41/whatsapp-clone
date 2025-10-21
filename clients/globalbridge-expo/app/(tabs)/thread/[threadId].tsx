import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  FlatList,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useLocalSearchParams } from 'expo-router';

import { useFlattenedMessages } from '~/hooks/use-threads';
import { useSession } from '~/hooks/use-session';

export default function ThreadScreen() {
  const { threadId } = useLocalSearchParams<{ threadId: string }>();
  const id = threadId ?? '';
  const { items, refetch, isLoading, isRefetching, realtime } = useFlattenedMessages(id);
  const { typingUsers, markRead, sendMessage, setTyping } = realtime;
  const authUserId = useSession((state) => state.tokens?.user.id);
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [sendError, setSendError] = useState<string | null>(null);
  const listRef = useRef<FlatList<(typeof items)[number]> | null>(null);
  const typingTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const composerDisabled = sending || !draft.trim();

  useEffect(() => {
    if (!items.length) return;
    void markRead(items[0].id);
    listRef.current?.scrollToOffset({ offset: 0, animated: true });
  }, [items, markRead]);

  const renderItem = useCallback(
    ({ item }: { item: (typeof items)[number] }) => {
      const isSelf = authUserId ? item.senderId === authUserId : false;
      const displayName = item.sender?.displayName ?? item.senderId;
      const timestamp = new Date(item.insertedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
      const isPending = item.id.startsWith('temp-');

      return (
        <View style={[styles.messageRow, isSelf ? styles.messageRowSelf : styles.messageRowOther]}>
          <View style={[styles.bubble, isSelf ? styles.bubbleSelf : styles.bubbleOther]}>
            {!isSelf ? <Text style={styles.sender}>{displayName}</Text> : null}
            <Text style={[styles.messageText, isSelf && styles.messageTextSelf]}>{item.content ?? '[attachment]'}</Text>
            <View style={styles.metaRow}>
              <Text style={[styles.timestamp, isSelf && styles.timestampSelf]}>{timestamp}</Text>
              {isSelf ? <PendingIndicator pending={isPending} /> : null}
            </View>
          </View>
        </View>
      );
    },
    [authUserId],
  );

  useEffect(
    () => () => {
      setTyping(false).catch(() => undefined);
      if (typingTimeoutRef.current) {
        clearTimeout(typingTimeoutRef.current);
        typingTimeoutRef.current = null;
      }
    },
    [setTyping],
  );

  const handleDraftChange = useCallback(
    (next: string) => {
      setDraft(next);
      const trimmed = next.trim();
      if (sendError) {
        setSendError(null);
      }
      if (trimmed.length === 0) {
        setTyping(false).catch(() => undefined);
        if (typingTimeoutRef.current) {
          clearTimeout(typingTimeoutRef.current);
          typingTimeoutRef.current = null;
        }
        return;
      }

      setTyping(true).catch(() => undefined);
      if (typingTimeoutRef.current) {
        clearTimeout(typingTimeoutRef.current);
      }
      typingTimeoutRef.current = setTimeout(() => {
        setTyping(false).catch(() => undefined);
        typingTimeoutRef.current = null;
      }, 3_000);
    },
    [sendError, setTyping],
  );

  const handleSend = useCallback(async () => {
    const trimmed = draft.trim();
    if (!trimmed || sending) return;
    setSending(true);
    try {
      await sendMessage({ content: trimmed, contentType: 'text' });
      setDraft('');
      setTyping(false).catch(() => undefined);
      if (typingTimeoutRef.current) {
        clearTimeout(typingTimeoutRef.current);
        typingTimeoutRef.current = null;
      }
    } catch (error) {
      console.warn('[thread-screen] Failed to send message', error);
      const message = error instanceof Error ? error.message : 'Unable to send message.';
      setSendError(message);
    } finally {
      setSending(false);
      setTyping(false).catch(() => undefined);
      if (typingTimeoutRef.current) {
        clearTimeout(typingTimeoutRef.current);
        typingTimeoutRef.current = null;
      }
    }
  }, [draft, sendMessage, sending, setTyping, setSendError]);

  const typingHint = useMemo(() => {
    if (typingUsers.length === 0) return null;
    if (typingUsers.length === 1) {
      const typingId = typingUsers[0];
      if (typingId === authUserId) {
        return 'You are typing…';
      }
      const name = items.find((message) => message.senderId === typingId)?.sender?.displayName ?? 'Someone';
      return `${name} is typing…`;
    }
    return 'Several people are typing…';
  }, [authUserId, items, typingUsers]);

  return (
    <KeyboardAvoidingView
      style={styles.wrapper}
      behavior={Platform.select({ ios: 'padding', android: undefined })}
      keyboardVerticalOffset={Platform.OS === 'ios' ? 80 : 0}
    >
      <FlatList
        ref={listRef}
        style={styles.list}
        data={items}
        keyExtractor={(item) => item.id}
        renderItem={renderItem}
        refreshControl={<RefreshControl refreshing={isRefetching || isLoading} onRefresh={refetch} />}
        contentContainerStyle={styles.contentContainer}
        ListEmptyComponent={
          !isLoading ? (
            <View style={styles.emptyState}>
              <Text style={styles.emptyTitle}>No messages yet</Text>
              <Text style={styles.emptySubtitle}>
                Start the conversation from another device to see it sync here.
              </Text>
            </View>
          ) : null
        }
        ListFooterComponent={
          typingHint ? (
            <View style={styles.typingContainer}>
              <Text style={styles.typingText}>{typingHint}</Text>
            </View>
          ) : null
        }
      />

      <View style={styles.composer}>
        <TextInput
          style={styles.input}
          placeholder="Write a message"
          value={draft}
          onChangeText={handleDraftChange}
          editable={!sending}
          onSubmitEditing={handleSend}
          multiline
          blurOnSubmit={false}
          returnKeyType="send"
        />
        <Pressable
          accessibilityRole="button"
          onPress={handleSend}
          disabled={composerDisabled}
          style={({ pressed }) => [
            styles.sendButton,
            pressed && !composerDisabled && styles.sendButtonPressed,
            composerDisabled && styles.sendButtonDisabled,
          ]}
        >
          <Text style={styles.sendLabel}>{sending ? 'Sending…' : 'Send'}</Text>
        </Pressable>
      </View>
      {sendError ? (
        <Text style={styles.errorBanner}>{sendError}</Text>
      ) : null}
    </KeyboardAvoidingView>
  );
}

function PendingIndicator({ pending }: { pending: boolean }) {
  if (!pending) return null;
  return <Text style={styles.pendingLabel}>Sending…</Text>;
}

const styles = StyleSheet.create({
  wrapper: {
    flex: 1,
    backgroundColor: '#f3f4f6',
  },
  list: {
    flex: 1,
    backgroundColor: '#f3f4f6',
  },
  contentContainer: {
    padding: 16,
    gap: 12,
  },
  messageRow: {
    flexDirection: 'row',
    marginVertical: 2,
  },
  messageRowSelf: {
    justifyContent: 'flex-end',
  },
  messageRowOther: {
    justifyContent: 'flex-start',
  },
  bubble: {
    maxWidth: '80%',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 18,
    gap: 4,
    shadowColor: '#000',
    shadowOpacity: 0.05,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 4 },
    elevation: 2,
  },
  bubbleSelf: {
    backgroundColor: '#2563eb',
    borderBottomRightRadius: 4,
  },
  bubbleOther: {
    backgroundColor: '#ffffff',
    borderBottomLeftRadius: 4,
  },
  sender: {
    fontSize: 14,
    fontWeight: '600',
    color: '#1f2937',
  },
  messageText: {
    fontSize: 16,
    color: '#111827',
  },
  messageTextSelf: {
    color: '#ffffff',
  },
  timestamp: {
    fontSize: 12,
    color: '#6b7280',
  },
  timestampSelf: {
    color: 'rgba(255,255,255,0.75)',
  },
  metaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  emptyState: {
    marginTop: 48,
    alignItems: 'center',
    gap: 8,
  },
  emptyTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#111827',
  },
  emptySubtitle: {
    fontSize: 14,
    color: '#6b7280',
    textAlign: 'center',
  },
  typingContainer: {
    paddingVertical: 8,
    alignItems: 'center',
  },
  typingText: {
    fontSize: 13,
    color: '#6b7280',
    fontStyle: 'italic',
  },
  composer: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: 12,
    paddingHorizontal: 16,
    paddingTop: 12,
    paddingBottom: Platform.OS === 'ios' ? 20 : 16,
    backgroundColor: '#ffffff',
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: '#e5e7eb',
  },
  input: {
    flex: 1,
    maxHeight: 120,
    borderRadius: 16,
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: '#f9fafb',
    fontSize: 16,
    color: '#111827',
  },
  sendButton: {
    backgroundColor: '#2563eb',
    borderRadius: 12,
    paddingHorizontal: 18,
    paddingVertical: 12,
  },
  sendButtonPressed: {
    opacity: 0.85,
  },
  sendButtonDisabled: {
    backgroundColor: '#93c5fd',
  },
  sendLabel: {
    color: '#ffffff',
    fontWeight: '600',
    fontSize: 16,
  },
  pendingLabel: {
    fontSize: 12,
    color: 'rgba(255,255,255,0.75)',
  },
  errorBanner: {
    textAlign: 'center',
    paddingHorizontal: 16,
    paddingVertical: 8,
    color: '#b91c1c',
    backgroundColor: '#fee2e2',
  },
});
