import { ActivityIndicator, FlatList, Pressable, RefreshControl, StyleSheet, Text, View } from 'react-native';
import { useCallback, useMemo } from 'react';
import { useRouter } from 'expo-router';

import { useThreads } from '~/hooks/use-threads';
import { useSession } from '~/hooks/use-session';
import { formatRelativeTime, formatShortDate } from '~/lib/date';
import type { ApiThread } from '~/api/schemas';

export default function InboxScreen() {
  const user = useSession((state) => state.tokens?.user);
  const { data, isLoading, refetch, isRefetching, error } = useThreads();
  const router = useRouter();
  const isInitialLoading = isLoading && !(data && data.length > 0);

  const onPressThread = useCallback(
    (id: string) => {
      router.push({ pathname: '/(tabs)/thread/[threadId]', params: { threadId: id } });
    },
    [router],
  );

  const contentData = useMemo(() => data ?? [], [data]);

  return (
    <FlatList
      style={styles.container}
      contentContainerStyle={styles.content}
      data={contentData}
      keyExtractor={(item) => item.id}
      refreshControl={<RefreshControl refreshing={isRefetching || isLoading} onRefresh={refetch} />}
      ListHeaderComponent={
        <View style={styles.header}>
          <Text style={styles.title}>Welcome back{user?.displayName ? `, ${user.displayName}` : ''}!</Text>
          <Text style={styles.subtitle}>Here are your recent conversations.</Text>
          {error ? (
            <View style={styles.errorBanner}>
              <Text style={styles.errorText}>Failed to load threads: {(error as Error).message}</Text>
              <Pressable accessibilityRole="button" onPress={() => refetch()} style={styles.retryButton}>
                <Text style={styles.retryLabel}>Try again</Text>
              </Pressable>
            </View>
          ) : null}
        </View>
      }
      renderItem={({ item }) => <ThreadListItem thread={item} onPress={onPressThread} />}
      ListEmptyComponent={
        isInitialLoading ? (
          <View style={styles.loadingState}>
            <ActivityIndicator size="large" color="#2563eb" />
            <Text style={styles.loadingLabel}>Loading conversations…</Text>
          </View>
        ) : (
          <View style={styles.emptyState}>
            <Text style={styles.emptyTitle}>No conversations yet</Text>
            <Text style={styles.emptySubtitle}>Once you connect bridges, threads will appear here automatically.</Text>
          </View>
        )
      }
    />
  );
}

interface ThreadListItemProps {
  thread: ApiThread;
  onPress: (id: string) => void;
}

function ThreadListItem({ thread, onPress }: ThreadListItemProps) {
  const lastMessageTime = formatShortDate(thread.lastMessageAt);
  const relativeTime = formatRelativeTime(thread.lastMessageAt);
  const participants = thread.participants?.map((participant) => participant.user?.displayName ?? '').filter(Boolean);
  const participantLabel = participants && participants.length > 0 ? participants.join(', ') : 'Unnamed participants';
  const typeLabel = thread.threadType?.toUpperCase?.() ?? 'THREAD';
  const metaParts = [relativeTime ? `Last activity ${relativeTime}` : 'No activity yet', typeLabel];

  return (
    <Pressable
      accessibilityRole="button"
      onPress={() => onPress(thread.id)}
      style={({ pressed }) => [styles.threadCard, pressed && styles.threadCardPressed]}
    >
      <View style={styles.threadHeaderRow}>
        <Text style={styles.threadTitle}>{thread.title ?? participantLabel}</Text>
        {lastMessageTime ? <Text style={styles.threadTimestamp}>{lastMessageTime}</Text> : null}
      </View>
      <Text style={styles.threadParticipants}>{participantLabel}</Text>
      <Text style={styles.threadMeta}>{metaParts.join(' • ')}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f9fafb',
  },
  content: {
    padding: 24,
    gap: 12,
  },
  header: {
    gap: 8,
    marginBottom: 12,
  },
  title: {
    fontSize: 24,
    fontWeight: '700',
    color: '#111827',
  },
  subtitle: {
    fontSize: 16,
    color: '#4b5563',
  },
  errorBanner: {
    marginTop: 8,
    borderRadius: 12,
    backgroundColor: '#fee2e2',
    paddingVertical: 10,
    paddingHorizontal: 14,
    gap: 8,
  },
  errorText: {
    color: '#b91c1c',
    fontSize: 14,
  },
  retryButton: {
    alignSelf: 'flex-start',
    backgroundColor: '#dc2626',
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 6,
  },
  retryLabel: {
    color: '#ffffff',
    fontSize: 13,
    fontWeight: '600',
  },
  loadingState: {
    marginTop: 48,
    alignItems: 'center',
    gap: 12,
  },
  loadingLabel: {
    fontSize: 14,
    color: '#4b5563',
  },
  threadCard: {
    backgroundColor: '#ffffff',
    padding: 20,
    borderRadius: 16,
    shadowColor: '#000',
    shadowOpacity: 0.05,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 6 },
    elevation: 2,
    gap: 6,
  },
  threadCardPressed: {
    opacity: 0.85,
  },
  threadHeaderRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    justifyContent: 'space-between',
    gap: 8,
  },
  threadTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#111827',
  },
  threadTimestamp: {
    fontSize: 12,
    color: '#6b7280',
  },
  threadParticipants: {
    fontSize: 13,
    color: '#4b5563',
  },
  threadMeta: {
    fontSize: 14,
    color: '#6b7280',
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
});
