package db

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

func setRLSGucs(ctx context.Context, tx pgx.Tx, userID, authRole, adminBypass, adminActorID string) error {
	if _, err := tx.Exec(ctx, "SELECT set_config('app.current_user_id', $1, true)", userID); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, "SELECT set_config('app.auth_service_role', $1, true)", authRole); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, "SELECT set_config('app.admin_bypass_rls', $1, true)", adminBypass); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, "SELECT set_config('app.admin_actor_id', $1, true)", adminActorID); err != nil {
		return err
	}
	return nil
}

func WithUserRLS(ctx context.Context, pool *pgxpool.Pool, userID uuid.UUID, fn func(tx pgx.Tx) error) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if err := setRLSGucs(ctx, tx, userID.String(), "", "", ""); err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func WithAuthWorkerRLS(ctx context.Context, pool *pgxpool.Pool, fn func(tx pgx.Tx) error) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if err := setRLSGucs(ctx, tx, "", "auth_worker", "", ""); err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func WithAdminBypassRLS(ctx context.Context, pool *pgxpool.Pool, fn func(tx pgx.Tx) error) error {
	return WithAdminBypassRLSAs(ctx, pool, uuid.Nil, fn)
}

func WithAdminBypassRLSAs(ctx context.Context, pool *pgxpool.Pool, actorAdminID uuid.UUID, fn func(tx pgx.Tx) error) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	actor := ""
	if actorAdminID != uuid.Nil {
		actor = actorAdminID.String()
	}
	if err := setRLSGucs(ctx, tx, "", "auth_worker", "telefam_admin_active", actor); err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
