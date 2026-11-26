import React, { useCallback, useEffect, useState } from 'react';
import { adminClient, AdminPrincipal, ApiError, ApprovalRequest } from '../api/adminClient';

interface Props {
  principal: AdminPrincipal;
  onChanged?: () => void;
}

export const ApprovalsView: React.FC<Props> = ({ principal, onChanged }) => {
  const [approvals, setApprovals] = useState<ApprovalRequest[]>([]);
  const [error, setError] = useState('');
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const res = await adminClient.listApprovals();
      setApprovals(res.approvals);
      setError('');
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Unable to load approvals.');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const decide = async (reqID: string, approve: boolean) => {
    setBusyId(reqID);
    try {
      await adminClient.decideApproval(reqID, approve, approve ? 'Approved by Super Admin' : 'Rejected by Super Admin');
      await load();
      onChanged?.();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Decision failed.');
    } finally {
      setBusyId(null);
    }
  };

  const isSuper = principal.role === 'super_admin';

  return (
    <div>
      <div className="toolbar">
        <div style={{ fontWeight: 700, fontSize: '0.95rem' }}>
          {isSuper ? 'Risky Action Approvals' : 'My Submitted Approval Requests'}
        </div>
        <button type="button" className="btn btn-secondary" onClick={load}>
          Refresh
        </button>
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
              <th>Requested By</th>
              <th>Action</th>
              <th>Target User</th>
              <th>Reason</th>
              <th>Status</th>
              <th>Created</th>
              {isSuper && <th>Decision</th>}
            </tr>
          </thead>
          <tbody>
            {approvals.length === 0 ? (
              <tr>
                <td colSpan={isSuper ? 7 : 6} style={{ color: 'var(--text-secondary)' }}>
                  No approval requests found.
                </td>
              </tr>
            ) : (
              approvals.map((a) => (
                <tr key={a.id}>
                  <td>
                    <div style={{ fontWeight: 600 }}>{a.requested_by_email}</div>
                    <div style={{ fontSize: '0.78rem', color: 'var(--text-secondary)' }}>{a.requested_by_role}</div>
                  </td>
                  <td>
                    <span className="badge badge-warn">{a.action_type}</span>
                  </td>
                  <td>{a.target_user_email || a.target_user_id}</td>
                  <td style={{ maxWidth: 260 }}>{a.reason}</td>
                  <td>
                    <span
                      className={`badge ${
                        a.status === 'pending'
                          ? 'badge-warn'
                          : a.status === 'rejected'
                          ? 'badge-danger'
                          : 'badge-ok'
                      }`}
                    >
                      {a.status}
                    </span>
                  </td>
                  <td>{new Date(a.created_at).toLocaleString()}</td>
                  {isSuper && (
                    <td>
                      {a.status === 'pending' ? (
                        <div className="actions-row">
                          <button
                            type="button"
                            className="btn btn-success btn-sm"
                            disabled={busyId === a.id}
                            onClick={() => decide(a.id, true)}
                          >
                            Approve & Execute
                          </button>
                          <button
                            type="button"
                            className="btn btn-danger btn-sm"
                            disabled={busyId === a.id}
                            onClick={() => decide(a.id, false)}
                          >
                            Reject
                          </button>
                        </div>
                      ) : (
                        <span style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>
                          {a.reviewed_by_email || 'Reviewed'}
                        </span>
                      )}
                    </td>
                  )}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
};
