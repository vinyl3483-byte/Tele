import React, { useCallback, useEffect, useState } from 'react';
import { adminClient, AdminPrincipal, ApiError, PostRecord } from '../api/adminClient';
import { IconSearch, IconTrash } from '../components/Icons';

interface Props {
  principal: AdminPrincipal;
}

export const PostsView: React.FC<Props> = ({ principal }) => {
  const [posts, setPosts] = useState<PostRecord[]>([]);
  const [query, setQuery] = useState('');
  const [feedback, setFeedback] = useState('');
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const res = await adminClient.listPosts(query);
      setPosts(res.posts);
    } catch (err) {
      setFeedback(err instanceof ApiError ? err.message : 'Unable to load posts.');
    }
  }, [query]);

  useEffect(() => {
    void load();
  }, [load]);

  const canRemove = principal.role === 'super_admin' || principal.granted_permissions.includes('remove_posts');

  const removePost = async (postId: string) => {
    setBusyId(postId);
    setFeedback('');
    try {
      await adminClient.removePost(postId);
      await load();
    } catch (err) {
      setFeedback(err instanceof ApiError ? err.message : 'Unable to remove post.');
    } finally {
      setBusyId(null);
    }
  };

  return (
    <div>
      <div className="toolbar">
        <div className="search-box">
          <IconSearch />
          <input
            className="input"
            placeholder="Search post text or author"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        <button type="button" className="btn btn-secondary" onClick={load}>
          Refresh
        </button>
      </div>

      {feedback && (
        <div className="alert alert-danger" style={{ marginBottom: 14 }}>
          <span>{feedback}</span>
        </div>
      )}

      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Author</th>
              <th>Type</th>
              <th>Content</th>
              <th>Content ID</th>
              <th>Created</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {posts.length === 0 ? (
              <tr>
                <td colSpan={6} style={{ color: 'var(--text-secondary)' }}>
                  No posts found.
                </td>
              </tr>
            ) : (
              posts.map((p) => (
                <tr key={p.post_id}>
                  <td>
                    <div style={{ fontWeight: 700 }}>{p.author_name || 'User'}</div>
                    <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>
                      {p.author_handle ? `@${p.author_handle}` : p.author_id.slice(0, 8)}
                    </div>
                  </td>
                  <td>
                    <span className="badge badge-neutral">
                      {p.post_type} {p.media_count > 0 ? `(${p.media_count})` : ''}
                    </span>
                  </td>
                  <td style={{ maxWidth: 340, wordBreak: 'break-word' }}>{p.body || '(media post)'}</td>
                  <td style={{ fontFamily: 'monospace', fontSize: '0.78rem' }}>
                    {p.content_fingerprint_hash.slice(0, 14)}
                  </td>
                  <td>{new Date(p.created_at).toLocaleString()}</td>
                  <td>
                    {canRemove && (
                      <button
                        type="button"
                        className="btn btn-danger btn-sm"
                        disabled={busyId === p.post_id}
                        onClick={() => removePost(p.post_id)}
                      >
                        <IconTrash /> Remove
                      </button>
                    )}
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
