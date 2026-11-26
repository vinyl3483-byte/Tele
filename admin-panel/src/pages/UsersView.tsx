import React, { useCallback, useEffect, useState } from 'react';
import { adminClient, AdminPrincipal, ApiError, UserRecord } from '../api/adminClient';
import { IconSearch, IconTrash } from '../components/Icons';

interface Props {
  principal: AdminPrincipal;
}

export const UsersView: React.FC<Props> = ({ principal }) => {
  const [users, setUsers] = useState<UserRecord[]>([]);
  const [query, setQuery] = useState('');
  const [feedback, setFeedback] = useState('');
  const [deleteTarget, setDeleteTarget] = useState<UserRecord | null>(null);
  const [deleteReason, setDeleteReason] = useState('');
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const res = await adminClient.listUsers(query);
      setUsers(res.users);
    } catch (err) {
      setFeedback(err instanceof ApiError ? err.message : 'Unable to load users.');
    }
  }, [query]);

  useEffect(() => {
    void load();
  }, [load]);

  const toggleSuspend = async (u: UserRecord) => {
    setBusyId(u.user_id);
    setFeedback('');
    try {
      await adminClient.setUserSuspended(u.user_id, !u.is_suspended);
      await load();
    } catch (err) {
      setFeedback(err instanceof ApiError ? err.message : 'Action failed.');
    } finally {
      setBusyId(null);
    }
  };

  const confirmDelete = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!deleteTarget) return;
    setBusyId(deleteTarget.user_id);
    setFeedback('');
    try {
      const res = await adminClient.deleteUserOrRequest(deleteTarget.user_id, deleteReason);
      setDeleteTarget(null);
      setDeleteReason('');
      if (res.requires_approval) {
        setFeedback('Delete user request submitted for Super Admin approval.');
      } else {
        setFeedback('User deleted.');
        await load();
      }
    } catch (err) {
      setFeedback(err instanceof ApiError ? err.message : 'Action failed.');
    } finally {
      setBusyId(null);
    }
  };

  const isSuper = principal.role === 'super_admin';

  return (
    <div>
      <div className="toolbar">
        <div className="search-box">
          <IconSearch />
          <input
            className="input"
            placeholder="Search email, name, or @username"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        <button type="button" className="btn btn-secondary" onClick={load}>
          Refresh
        </button>
      </div>

      {feedback && (
        <div className="alert alert-warning" style={{ marginBottom: 14 }}>
          <span>{feedback}</span>
        </div>
      )}

      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>User</th>
              <th>Email</th>
              <th>Provider</th>
              <th>Risk</th>
              <th>Status</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {users.length === 0 ? (
              <tr>
                <td colSpan={6} style={{ color: 'var(--text-secondary)' }}>
                  No users found.
                </td>
              </tr>
            ) : (
              users.map((u) => (
                <tr key={u.user_id}>
                  <td>
                    <div style={{ fontWeight: 700 }}>{u.full_name || 'Unset'}</div>
                    <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>
                      {u.username ? `@${u.username}` : u.user_id.slice(0, 8)}
                    </div>
                  </td>
                  <td>{u.email}</td>
                  <td>
                    <span className="badge badge-neutral">{u.auth_provider}</span>
                  </td>
                  <td>
                    <span className={`badge ${u.risk_score >= 50 ? 'badge-danger' : u.risk_score >= 25 ? 'badge-warn' : 'badge-ok'}`}>
                      {u.risk_score}
                    </span>
                  </td>
                  <td>
                    {u.is_suspended ? (
                      <span className="badge badge-danger">Suspended</span>
                    ) : u.profile_completed ? (
                      <span className="badge badge-ok">Active</span>
                    ) : (
                      <span className="badge badge-warn">Onboarding</span>
                    )}
                  </td>
                  <td>
                    <div className="actions-row">
                      {principal.granted_permissions.includes('suspend_users') || isSuper ? (
                        <button
                          type="button"
                          className="btn btn-warning btn-sm"
                          disabled={busyId === u.user_id}
                          onClick={() => toggleSuspend(u)}
                        >
                          {u.is_suspended ? 'Restore' : 'Suspend'}
                        </button>
                      ) : null}
                      <button
                        type="button"
                        className="btn btn-danger btn-sm"
                        disabled={busyId === u.user_id}
                        onClick={() => setDeleteTarget(u)}
                      >
                        <IconTrash />
                        {isSuper ? 'Delete User' : 'Request Delete'}
                      </button>
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {deleteTarget && (
        <div className="modal-backdrop">
          <div className="modal-card">
            <div className="modal-header">
              <h3 style={{ fontWeight: 700 }}>
                {isSuper ? 'Delete User Account' : 'Request Super Admin Approval'}
              </h3>
            </div>
            <p style={{ fontSize: '0.875rem', color: 'var(--text-secondary)', marginBottom: 14 }}>
              Target: {deleteTarget.email}
            </p>
            <form onSubmit={confirmDelete}>
              <div className="field">
                <label htmlFor="delete-reason">Reason</label>
                <textarea
                  id="delete-reason"
                  className="textarea"
                  rows={3}
                  required={!isSuper}
                  value={deleteReason}
                  onChange={(e) => setDeleteReason(e.target.value)}
                  placeholder="Enter moderation reason"
                />
              </div>
              <div className="actions-row" style={{ justifyContent: 'flex-end' }}>
                <button type="button" className="btn btn-secondary" onClick={() => setDeleteTarget(null)}>
                  Cancel
                </button>
                <button type="submit" className="btn btn-danger" disabled={busyId === deleteTarget.user_id}>
                  {isSuper ? 'Confirm Delete' : 'Submit Request'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
