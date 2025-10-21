export function formatRelativeTime(isoTimestamp: string | null | undefined) {
  if (!isoTimestamp) return '';
  const parsed = new Date(isoTimestamp);
  if (Number.isNaN(parsed.getTime())) return '';

  const now = Date.now();
  const diffMs = parsed.getTime() - now;
  const diffSeconds = Math.round(diffMs / 1000);

  const ranges: Array<{ limit: number; divisor: number; unit: Intl.RelativeTimeFormatUnit }> = [
    { limit: 60, divisor: 1, unit: 'second' },
    { limit: 60 * 60, divisor: 60, unit: 'minute' },
    { limit: 60 * 60 * 24, divisor: 60 * 60, unit: 'hour' },
    { limit: 60 * 60 * 24 * 7, divisor: 60 * 60 * 24, unit: 'day' },
    { limit: 60 * 60 * 24 * 30, divisor: 60 * 60 * 24 * 7, unit: 'week' },
    { limit: 60 * 60 * 24 * 365, divisor: 60 * 60 * 24 * 30, unit: 'month' },
    { limit: Number.POSITIVE_INFINITY, divisor: 60 * 60 * 24 * 365, unit: 'year' },
  ];

  const absSeconds = Math.abs(diffSeconds);

  const supportsRelativeTime = typeof Intl !== 'undefined' && typeof Intl.RelativeTimeFormat === 'function';
  const formatter = supportsRelativeTime
    ? new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' })
    : null;

  for (const { limit, divisor, unit } of ranges) {
    if (absSeconds < limit) {
      const value = Math.round(diffSeconds / divisor);
      if (formatter) {
        return formatter.format(value, unit);
      }
      const unitLabel = unit.replace(/s$/, '');
      return `${Math.abs(value)} ${unitLabel}${Math.abs(value) === 1 ? '' : 's'} ${
        value >= 0 ? 'from now' : 'ago'
      }`;
    }
  }

  return parsed.toLocaleDateString();
}

export function formatShortDate(isoTimestamp: string | null | undefined) {
  if (!isoTimestamp) return '';
  const parsed = new Date(isoTimestamp);
  if (Number.isNaN(parsed.getTime())) return '';

  const now = new Date();
  const sameDay =
    parsed.getFullYear() === now.getFullYear() &&
    parsed.getMonth() === now.getMonth() &&
    parsed.getDate() === now.getDate();

  if (sameDay) {
    return parsed.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }

  return parsed.toLocaleDateString([], { month: 'short', day: 'numeric' });
}
