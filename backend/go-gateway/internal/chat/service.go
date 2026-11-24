package chat

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/telefam/company/backend/go-gateway/internal/config"
	"github.com/telefam/company/backend/go-gateway/internal/db"
	"github.com/telefam/company/backend/go-gateway/internal/security"
)

type Service struct {
	cfg  *config.Config
	pool *pgxpool.Pool
}

func NewService(cfg *config.Config, pool *pgxpool.Pool) *Service {
	return &Service{cfg: cfg, pool: pool}
}

type ConversationDTO struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	UpdatedAt int64  `json:"updated_at"`
}

type MessageDTO struct {
	ID               string `json:"id"`
	ConversationID   string `json:"conversation_id"`
	SenderID         string `json:"sender_id"`
	ClientMutationID string `json:"client_mutation_id"`
	Body             string `json:"body"`
	CreatedAt        int64  `json:"created_at"`
}

type OfflineMutation struct {
	MutationID string          `json:"mutation_id"`
	ActionType string          `json:"action_type"`
	Payload    json.RawMessage `json:"payload"`
}

func (s *Service) ListConversations(ctx context.Context, userID uuid.UUID) ([]ConversationDTO, int, error) {
	var out []ConversationDTO
	err := db.WithUserRLS(ctx, s.pool, userID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT id, title_encrypted, updated_at
			FROM conversations
			ORDER BY updated_at DESC
		`)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var id uuid.UUID
			var encTitle []byte
			var upd time.Time
			if err := rows.Scan(&id, &encTitle, &upd); err != nil {
				return err
			}
			pt, dErr := security.DecryptAtRest(s.cfg.MasterKey, encTitle, "conversations.title")
			if dErr != nil {
				continue
			}
			out = append(out, ConversationDTO{
				ID:        id.String(),
				Title:     string(pt),
				UpdatedAt: upd.UnixMilli(),
			})
		}
		return rows.Err()
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return out, http.StatusOK, nil
}

func (s *Service) CreateConversation(ctx context.Context, userID uuid.UUID, title string) (*ConversationDTO, int, error) {
	encTitle, err := security.EncryptAtRest(s.cfg.MasterKey, []byte(title), "conversations.title")
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	var convID uuid.UUID
	var upd time.Time
	err = db.WithUserRLS(ctx, s.pool, userID, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `
			INSERT INTO conversations (created_by, title_encrypted)
			VALUES ($1, $2)
			RETURNING id, updated_at
		`, userID, encTitle).Scan(&convID, &upd); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `
			INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1, $2)
		`, convID, userID)
		return err
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return &ConversationDTO{ID: convID.String(), Title: title, UpdatedAt: upd.UnixMilli()}, http.StatusCreated, nil
}

func (s *Service) ListMessages(ctx context.Context, userID, convID uuid.UUID, sinceMs int64) ([]MessageDTO, int, error) {
	var out []MessageDTO
	sinceTime := time.UnixMilli(sinceMs).UTC()
	err := db.WithUserRLS(ctx, s.pool, userID, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT id, conversation_id, sender_id, client_mutation_id, body_encrypted, created_at
			FROM messages
			WHERE conversation_id = $1 AND deleted_at IS NULL AND created_at >= $2
			ORDER BY created_at ASC
			LIMIT 200
		`, convID, sinceTime)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var id, cID, sender uuid.UUID
			var mutID string
			var encBody []byte
			var created time.Time
			if err := rows.Scan(&id, &cID, &sender, &mutID, &encBody, &created); err != nil {
				return err
			}
			pt, dErr := security.DecryptAtRest(s.cfg.MasterKey, encBody, "messages.body")
			if dErr != nil {
				continue
			}
			out = append(out, MessageDTO{
				ID:               id.String(),
				ConversationID:   cID.String(),
				SenderID:         sender.String(),
				ClientMutationID: mutID,
				Body:             string(pt),
				CreatedAt:        created.UnixMilli(),
			})
		}
		return rows.Err()
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return out, http.StatusOK, nil
}

func (s *Service) ApplyMutationsBatch(ctx context.Context, userID uuid.UUID, devFP string, batch []OfflineMutation) ([]string, int, error) {
	acked := make([]string, 0, len(batch))
	err := db.WithUserRLS(ctx, s.pool, userID, func(tx pgx.Tx) error {
		for _, m := range batch {
			encPayload, err := security.EncryptAtRest(s.cfg.MasterKey, m.Payload, "offline_mutations.payload")
			if err != nil {
				return err
			}
			tag, err := tx.Exec(ctx, `
				INSERT INTO offline_mutations (user_id, device_fp_hash, client_mutation_id, action_type, payload_encrypted)
				VALUES ($1, $2, $3, $4, $5)
				ON CONFLICT (user_id, client_mutation_id) DO NOTHING
			`, userID, devFP, m.MutationID, m.ActionType, encPayload)
			if err != nil {
				return err
			}
			if tag.RowsAffected() == 1 {
				switch m.ActionType {
				case "send_message":
					var p struct {
						ConversationID string `json:"conversation_id"`
						Body           string `json:"body"`
					}
					if json.Unmarshal(m.Payload, &p) == nil {
						if convID, pErr := uuid.Parse(p.ConversationID); pErr == nil {
							encBody, _ := security.EncryptAtRest(s.cfg.MasterKey, []byte(p.Body), "messages.body")
							_, _ = tx.Exec(ctx, `
								INSERT INTO messages (conversation_id, sender_id, client_mutation_id, body_encrypted)
								VALUES ($1, $2, $3, $4)
								ON CONFLICT (sender_id, client_mutation_id) DO NOTHING
							`, convID, userID, m.MutationID, encBody)
							_, _ = tx.Exec(ctx, `UPDATE conversations SET updated_at = NOW() WHERE id = $1`, convID)
						}
					}
				case "delete_message":
					var p struct {
						MessageID string `json:"message_id"`
					}
					if json.Unmarshal(m.Payload, &p) == nil {
						if msgID, pErr := uuid.Parse(p.MessageID); pErr == nil {
							_, _ = tx.Exec(ctx, `UPDATE messages SET deleted_at = NOW() WHERE id = $1 AND sender_id = $2`, msgID, userID)
						}
					}
				case "follow_user":
					var p struct {
						TargetUserID string `json:"target_user_id"`
					}
					if json.Unmarshal(m.Payload, &p) == nil {
						if targetID, pErr := uuid.Parse(p.TargetUserID); pErr == nil && targetID != userID {
							_, _ = tx.Exec(ctx, `
								INSERT INTO user_follows (follower_id, followee_id)
								VALUES ($1, $2)
								ON CONFLICT (follower_id, followee_id) DO NOTHING
							`, userID, targetID)
						}
					}
				case "unfollow_user":
					var p struct {
						TargetUserID string `json:"target_user_id"`
					}
					if json.Unmarshal(m.Payload, &p) == nil {
						if targetID, pErr := uuid.Parse(p.TargetUserID); pErr == nil && targetID != userID {
							_, _ = tx.Exec(ctx, `
								DELETE FROM user_follows
								WHERE follower_id = $1 AND followee_id = $2
							`, userID, targetID)
						}
					}
				}
			}
			acked = append(acked, m.MutationID)
		}
		return nil
	})
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return acked, http.StatusOK, nil
}
