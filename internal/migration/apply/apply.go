package apply

import (
	"context"
	"fmt"
	"os"

	"github.com/go-errors/errors"
	"github.com/jackc/pgx/v4"
	"github.com/spf13/afero"
	"github.com/supabase/cli/internal/db/seed"
	"github.com/supabase/cli/internal/migration/list"
	"github.com/supabase/cli/internal/utils"
	"github.com/supabase/cli/pkg/migration"
)

func MigrateAndSeed(ctx context.Context, version string, conn *pgx.Conn, fsys afero.Fs, seedConfig seed.Config) error {
	migrations, err := list.LoadPartialMigrations(version, fsys)
	if err != nil {
		return err
	}
	if err := migration.ApplyMigrations(ctx, migrations, conn, afero.NewIOFS(fsys)); err != nil {
		return err
	}

	if seedConfig.IsProvided {
		if seedConfig.Path == "" {
			fmt.Println("Skipping database seeding...")
			return nil
		}
	} else {
		// Use default path if seed-path was not provided
		seedConfig.Path = utils.SeedDataPath
	}

	if err := SeedDatabase(ctx, conn, fsys, seedConfig.Path); err != nil {
		return err
	}

	return nil
}

func SeedDatabase(ctx context.Context, conn *pgx.Conn, fsys afero.Fs, seedPath string) error {
	err := migration.SeedData(ctx, []string{seedPath}, conn, afero.NewIOFS(fsys))
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return err
}

func CreateCustomRoles(ctx context.Context, conn *pgx.Conn, fsys afero.Fs) error {
	err := migration.SeedGlobals(ctx, []string{utils.CustomRolesPath}, conn, afero.NewIOFS(fsys))
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return err
}
