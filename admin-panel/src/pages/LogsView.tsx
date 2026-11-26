import React, { useCallback, useEffect, useState } from 'react';
import { ActivityLogRecord, adminClient, ApiError } from '../api/adminClient';
import { IconSearch } from '../components/Icons';

export const LogsView: React.FC = () => {
  const [logs, setLogs] = useState<ActivityLogRecord[]>([]);
  const [filterSource, setFilterSource] = useState<'all' | 'admin' | 'user_risk'>('all');
  const [query, setQuery] = useState('');
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    try {
      const res = await adminClient.listLogs(200);
      setLogs(res.logs);
      setError('');
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Unable to load activity logs.');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const filtered = logs.filter((l) => {
    if (filterSource !== 'all' && l.source !== filterSource) return false;
    if (!query.trim()) return true;
    const q = query.toLowerCase();
    return (
      l.actor_email.toLowerCase().includes(q) ||
      l.action_type.toLowerCase().includes(q) ||
      l.actor_role.toLowerCase().includes(q) ||
      l.outcome.toLowerCase().includes(q)
    );
  });

  return (
    <div>
      <div className="toolbar">
        <div className="search-box">
          <IconSearch />
          <input
            className="input"
            placeholder="Filter by email, role, or action"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        <div className="actions-row">
          <button
            type="button"
            className={`btn btn-sm ${filterSource === 'all' ? 'btn-primary' : 'btn-secondary'}`}
            onClick={() => setFilterSource('all')}
          >
            All
          </button>
          <button
            type="button"
            className={`btn btn-sm ${filterSource === 'admin' ? 'btn-primary' : 'btn-secondary'}`}
            onClick={() => setFilterSource('admin')}
          >
            Admins & Moderators
          </button>
          <button
            type="button"
            className={`btn btn-sm ${filterSource === 'user_risk' ? 'btn-primary' : 'btn-secondary'}`}
            onClick={() => setFilterSource('user_risk')}
          >
            User Risk
          </button>
          <button type="button" className="btn btn-secondary btn-sm" onClick={load}>
            Refresh
          </button>
        </div>
      </div>

      {error && (
        <div className="alert alert-danger" style={{ marginBottom: 14 }}>
          <span>{error}</span>
        </div>
      )}

      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Time</th>
              <th>Source</th>
              <th>Actor</th>
              <th>Role</th>
              <th>Action</th>
              <th>Target</th>
              <th>Outcome</th>
            </tr>
          </thead>
          <tbody>
            {filtered.length === 0 ? (
              <tr>
                <td colSpan={7} style={{ color: 'var(--text-secondary)' }}>
                  No activity logs match filter.
                </td>
              </tr>
            ) : (
              filtered.map((l) => (
                <tr key={l.id}>
                  <td>{new Date(l.created_at).toLocaleString()}</td>
                  <td>
                    <span className="badge badge-neutral">{l.source}</span>
                  </td>
                  <td>{l.actor_email}</td>
                  <td>
                    <span className="badge badge-neutral">{l.actor_role}</span>
                  </td>
                  <td style={{ fontWeight: 600 }}>{l.action_type}</td>
                  <td style={{ fontFamily: 'monospace', fontSize: '0.78rem' }}>
                    {l.target_user_id || l.target_post_id || '—'}
                  </td>
                  <td>
                    <span
                      className={`badge ${
                        l.outcome === 'denied' || l.outcome === 'blocked'
                          ? 'badge-danger'
                          : l.outcome === 'pending_approval'
                          ? 'badge-warn'
                          : 'badge-ok'
                      }`}
                    >
                      {l.outcome}
                    </span>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
};
