package db

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

func WithUserRLS(ctx context.Context, pool *pgxpool.Pool, userID uuid.UUID, fn func(tx pgx.Tx) error) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx, "SELECT set_config('app.current_user_id', $1, true)", userID.String()); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, "SELECT set_config('app.auth_service_role', '', true)"); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, "SELECT set_config('app.admin_bypass_rls', '', true)"); err != nil {
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

	if _, err := tx.Exec(ctx, "SELECT set_config('app.auth_service_role', 'auth_worker', true)"); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, "SELECT set_config('app.admin_bypass_rls', '', true)"); err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func WithAdminBypassRLS(ctx context.Context, pool *pgxpool.Pool, fn func(tx pgx.Tx) error) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx, "SELECT set_config('app.current_user_id', '', true)"); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, "SELECT set_config('app.auth_service_role', 'auth_worker', true)"); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, "SELECT set_config('app.admin_bypass_rls', 'telefam_admin_active', true)"); err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
