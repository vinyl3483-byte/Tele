import React, { useState } from 'react';
import { adminClient, ApiError } from '../api/adminClient';
import { IconLock, TelefamEmblem } from '../components/Icons';

interface Props {
  email: string;
  initialTempPassword?: string;
  onPasswordSaved: () => void;
  onLogout: () => void;
}

export const ForcePasswordChangeView: React.FC<Props> = ({
  email,
  initialTempPassword = '',
  onPasswordSaved,
  onLogout,
}) => {
  const [currentPassword, setCurrentPassword] = useState(initialTempPassword);
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg('');
    if (newPassword !== confirmPassword) {
      setErrorMsg('New passwords do not match.');
      return;
    }
    if (newPassword === currentPassword) {
      setErrorMsg('New password must differ from your temporary password.');
      return;
    }
    setLoading(true);
    try {
      await adminClient.changePassword(currentPassword, newPassword);
      onPasswordSaved();
    } catch (err) {
      setErrorMsg(err instanceof ApiError ? err.message : 'Unable to save new password.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="auth-shell">
      <div className="auth-card">
        <div className="brand-header">
          <TelefamEmblem size={52} />
          <h1>Create New Password</h1>
          <p>{email}</p>
        </div>

        <div className="alert alert-warning">
          <IconLock size={18} />
          <span>You signed in with a temporary password. Create and save a permanent password to continue.</span>
        </div>

        {errorMsg && (
          <div className="alert alert-danger" role="alert">
            <span>{errorMsg}</span>
          </div>
        )}

        <form onSubmit={handleSubmit}>
          <div className="field">
            <label htmlFor="tmp-current">Temporary Password</label>
            <input
              id="tmp-current"
              className="input"
              type="password"
              required
              value={currentPassword}
              onChange={(e) => setCurrentPassword(e.target.value)}
            />
          </div>
          <div className="field">
            <label htmlFor="tmp-new">New Password (10+ chars, upper, lower, number/symbol)</label>
            <input
              id="tmp-new"
              className="input"
              type="password"
              required
              minLength={10}
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
            />
          </div>
          <div className="field">
            <label htmlFor="tmp-confirm">Confirm New Password</label>
            <input
              id="tmp-confirm"
              className="input"
              type="password"
              required
              minLength={10}
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
            />
          </div>
          <div className="actions-row">
            <button type="submit" className="btn btn-primary" style={{ flex: 1 }} disabled={loading}>
              {loading ? 'Saving...' : 'Save Password'}
            </button>
            <button type="button" className="btn btn-secondary" onClick={onLogout}>
              Sign Out
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
