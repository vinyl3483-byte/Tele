import React, { useEffect, useState } from 'react';
import { adminClient, DashboardStats } from '../api/adminClient';

export const DashboardView: React.FC = () => {
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [error, setError] = useState('');

  const load = async () => {
    try {
      setStats(await adminClient.dashboard());
      setError('');
    } catch {
      setError('Unable to load dashboard.');
    }
  };

  useEffect(() => {
    void load();
  }, []);

  if (error) {
    return <div className="alert alert-danger">{error}</div>;
  }

  return (
    <div>
      <div className="kpi-grid">
        <div className="card">
          <div className="kpi-label">Registered Users</div>
          <div className="kpi-value">{stats?.total_users ?? '—'}</div>
        </div>
        <div className="card">
          <div className="kpi-label">Published Posts</div>
          <div className="kpi-value">{stats?.total_posts ?? '—'}</div>
        </div>
        <div className="card">
          <div className="kpi-label">Active Staff</div>
          <div className="kpi-value">{stats ? stats.total_staff - stats.paused_staff : '—'}</div>
        </div>
        <div className="card">
          <div className="kpi-label">Pending Approvals</div>
          <div className="kpi-value">{stats?.pending_approvals ?? '—'}</div>
        </div>
        <div className="card">
          <div className="kpi-label">Active Lockouts</div>
          <div className="kpi-value">{stats?.active_lockouts ?? '—'}</div>
        </div>
      </div>

      <div className="card" style={{ marginBottom: 16 }}>
        <div className="toolbar" style={{ marginBottom: 12 }}>
          <h2 style={{ fontSize: '1rem', fontWeight: 700 }}>Recent Activity</h2>
          <button type="button" className="btn btn-secondary btn-sm" onClick={load}>
            Refresh
          </button>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Time</th>
                <th>Actor</th>
                <th>Role</th>
                <th>Action</th>
                <th>Outcome</th>
              </tr>
            </thead>
            <tbody>
              {(stats?.recent_logs ?? []).length === 0 ? (
                <tr>
                  <td colSpan={5} style={{ color: 'var(--text-secondary)' }}>
                    No recent activity recorded.
                  </td>
                </tr>
              ) : (
                stats?.recent_logs.map((log) => (
                  <tr key={log.id}>
                    <td>{new Date(log.created_at).toLocaleString()}</td>
                    <td>{log.actor_email}</td>
                    <td>
                      <span className="badge badge-neutral">{log.actor_role}</span>
                    </td>
                    <td>{log.action_type}</td>
                    <td>
                      <span
                        className={`badge ${
                          log.outcome === 'denied' || log.outcome === 'blocked'
                            ? 'badge-danger'
                            : log.outcome === 'pending_approval'
                            ? 'badge-warn'
                            : 'badge-ok'
                        }`}
                      >
                        {log.outcome}
                      </span>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};
