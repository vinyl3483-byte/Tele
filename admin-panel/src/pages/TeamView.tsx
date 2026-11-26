import React, { useCallback, useEffect, useState } from 'react';
import { adminClient, AdminPrincipal, ApiError, StaffMember } from '../api/adminClient';
import { IconClose, IconPause, IconPlay, IconPlus, IconTrash } from '../components/Icons';

const ALL_PERMISSIONS = [
  { key: 'view_users', label: 'View Users' },
  { key: 'view_posts', label: 'View Posts' },
  { key: 'view_logs', label: 'View Logs' },
  { key: 'remove_posts', label: 'Remove Posts' },
  { key: 'request_delete_user', label: 'Request User Delete' },
  { key: 'suspend_users', label: 'Suspend Users' },
  { key: 'sanitize_media', label: 'Sanitize Media' },
];

interface Props {
  principal: AdminPrincipal;
}

export const TeamView: React.FC<Props> = ({ principal }) => {
  const [staff, setStaff] = useState<StaffMember[]>([]);
  const [error, setError] = useState('');
  const [showAdd, setShowAdd] = useState(false);
  const [editing, setEditing] = useState<StaffMember | null>(null);

  const [email, setEmail] = useState('');
  const [fullName, setFullName] = useState('');
  const [role, setRole] = useState<'moderator' | 'admin' | 'super_admin'>('moderator');
  const [password, setPassword] = useState('');
  const [isTemp, setIsTemp] = useState(true);
  const [perms, setPerms] = useState<string[]>(['view_users', 'view_posts', 'remove_posts', 'request_delete_user']);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const res = await adminClient.listStaff();
      setStaff(res.staff);
      setError('');
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Unable to load staff.');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const togglePerm = (key: string) => {
    setPerms((prev) => (prev.includes(key) ? prev.filter((p) => p !== key) : [...prev, key]));
  };

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      await adminClient.createStaff({
        email,
        full_name: fullName,
        role,
        password,
        is_temporary: isTemp,
        permissions: perms,
      });
      setShowAdd(false);
      setEmail('');
      setFullName('');
      setPassword('');
      setIsTemp(true);
      await load();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Unable to add staff.');
    } finally {
      setBusy(false);
    }
  };

  const handleUpdateRole = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editing) return;
    setBusy(true);
    try {
      await adminClient.updateStaffRole(editing.id, role, perms);
      setEditing(null);
      await load();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Unable to update role.');
    } finally {
      setBusy(false);
    }
  };

  const handlePauseToggle = async (member: StaffMember) => {
    setBusy(true);
    try {
      await adminClient.setStaffPaused(member.id, !member.is_paused);
      await load();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Action failed.');
    } finally {
      setBusy(false);
    }
  };

  const handleRemove = async (member: StaffMember) => {
    setBusy(true);
    try {
      await adminClient.removeStaff(member.id);
      await load();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Unable to remove staff.');
    } finally {
      setBusy(false);
    }
  };

  const openEdit = (member: StaffMember) => {
    setEditing(member);
    setRole(member.role);
    setPerms(member.granted_permissions);
  };

  return (
    <div>
      <div className="toolbar">
        <div style={{ fontWeight: 700, fontSize: '0.95rem' }}>Admins & Moderators</div>
        <div className="actions-row">
          <button type="button" className="btn btn-secondary" onClick={load}>
            Refresh
          </button>
          <button
            type="button"
            className="btn btn-primary"
            onClick={() => {
              setRole('moderator');
              setPerms(['view_users', 'view_posts', 'remove_posts', 'request_delete_user']);
              setShowAdd(true);
            }}
          >
            <IconPlus /> Add Admin / Moderator
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
              <th>Member</th>
              <th>Role</th>
              <th>Permissions</th>
              <th>Password Status</th>
              <th>Activity</th>
              <th>Controls</th>
            </tr>
          </thead>
          <tbody>
            {staff.map((m) => {
              const isSelf = m.id === principal.id;
              return (
                <tr key={m.id}>
                  <td>
                    <div style={{ fontWeight: 700 }}>{m.full_name}</div>
                    <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>{m.email}</div>
                  </td>
                  <td>
                    <span className="badge badge-neutral">{m.role}</span>
                  </td>
                  <td>
                    <div className="actions-row" style={{ gap: 4 }}>
                      {(m.granted_permissions || []).map((p) => (
                        <span key={p} className="badge badge-neutral">
                          {p}
                        </span>
                      ))}
                    </div>
                  </td>
                  <td>
                    {m.must_change_password ? (
                      <span className="badge badge-warn">Temp Reset Pending</span>
                    ) : (
                      <span className="badge badge-ok">Permanent</span>
                    )}
                  </td>
                  <td>
                    {m.is_paused ? (
                      <span className="badge badge-danger">Paused</span>
                    ) : (
                      <span className="badge badge-ok">Active</span>
                    )}
                  </td>
                  <td>
                    <div className="actions-row">
                      <button
                        type="button"
                        className="btn btn-secondary btn-sm"
                        disabled={busy || isSelf}
                        onClick={() => openEdit(m)}
                      >
                        Roles
                      </button>
                      <button
                        type="button"
                        className={`btn btn-sm ${m.is_paused ? 'btn-success' : 'btn-warning'}`}
                        disabled={busy || isSelf}
                        onClick={() => handlePauseToggle(m)}
                      >
                        {m.is_paused ? <IconPlay /> : <IconPause />}
                        {m.is_paused ? 'Resume' : 'Pause'}
                      </button>
                      <button
                        type="button"
                        className="btn btn-danger btn-sm"
                        disabled={busy || isSelf}
                        onClick={() => handleRemove(m)}
                      >
                        <IconTrash /> Remove
                      </button>
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {showAdd && (
        <div className="modal-backdrop">
          <div className="modal-card">
            <div className="modal-header">
              <h3 style={{ fontWeight: 700 }}>Add Staff Member</h3>
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => setShowAdd(false)}>
                <IconClose />
              </button>
            </div>
            <form onSubmit={handleCreate}>
              <div className="field">
                <label htmlFor="staff-name">Full Name</label>
                <input
                  id="staff-name"
                  className="input"
                  required
                  value={fullName}
                  onChange={(e) => setFullName(e.target.value)}
                />
              </div>
              <div className="field">
                <label htmlFor="staff-email">Email</label>
                <input
                  id="staff-email"
                  className="input"
                  type="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                />
              </div>
              <div className="field">
                <label htmlFor="staff-role">Role</label>
                <select
                  id="staff-role"
                  className="select"
                  value={role}
                  onChange={(e) => setRole(e.target.value as 'moderator' | 'admin' | 'super_admin')}
                >
                  <option value="moderator">Moderator</option>
                  <option value="admin">Admin</option>
                  <option value="super_admin">Super Admin</option>
                </select>
              </div>
              <div className="field">
                <label htmlFor="staff-password">Initial / Temporary Password (10+ chars)</label>
                <input
                  id="staff-password"
                  className="input"
                  type="password"
                  required
                  minLength={10}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                />
              </div>
              <label className="perm-check" style={{ marginBottom: 16 }}>
                <input type="checkbox" checked={isTemp} onChange={(e) => setIsTemp(e.target.checked)} />
                <span>Temporary password (force password change after login)</span>
              </label>
              <div className="field">
                <label>Granted Permissions</label>
                <div className="perm-grid">
                  {ALL_PERMISSIONS.map((p) => (
                    <label key={p.key} className="perm-check">
                      <input
                        type="checkbox"
                        checked={perms.includes(p.key)}
                        onChange={() => togglePerm(p.key)}
                      />
                      <span>{p.label}</span>
                    </label>
                  ))}
                </div>
              </div>
              <div className="actions-row" style={{ justifyContent: 'flex-end', marginTop: 18 }}>
                <button type="button" className="btn btn-secondary" onClick={() => setShowAdd(false)}>
                  Cancel
                </button>
                <button type="submit" className="btn btn-primary" disabled={busy}>
                  Create Member
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {editing && (
        <div className="modal-backdrop">
          <div className="modal-card">
            <div className="modal-header">
              <h3 style={{ fontWeight: 700 }}>Update Role & Permissions</h3>
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => setEditing(null)}>
                <IconClose />
              </button>
            </div>
            <p style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', marginBottom: 14 }}>
              {editing.email}
            </p>
            <form onSubmit={handleUpdateRole}>
              <div className="field">
                <label htmlFor="edit-role">Role</label>
                <select
                  id="edit-role"
                  className="select"
                  value={role}
                  onChange={(e) => setRole(e.target.value as 'moderator' | 'admin' | 'super_admin')}
                >
                  <option value="moderator">Moderator</option>
                  <option value="admin">Admin</option>
                  <option value="super_admin">Super Admin</option>
                </select>
              </div>
              <div className="field">
                <label>Granted Permissions</label>
                <div className="perm-grid">
                  {ALL_PERMISSIONS.map((p) => (
                    <label key={p.key} className="perm-check">
                      <input
                        type="checkbox"
                        checked={perms.includes(p.key)}
                        onChange={() => togglePerm(p.key)}
                      />
                      <span>{p.label}</span>
                    </label>
                  ))}
                </div>
              </div>
              <div className="actions-row" style={{ justifyContent: 'flex-end', marginTop: 18 }}>
                <button type="button" className="btn btn-secondary" onClick={() => setEditing(null)}>
                  Cancel
                </button>
                <button type="submit" className="btn btn-primary" disabled={busy}>
                  Save Changes
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
