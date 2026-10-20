// Package migrationfiles exposes embedded SQL at the MyGO infrastructure boundary.
package migrationfiles

import "embed"

//go:embed migrations/*.sql
var files embed.FS

func Read(name string) (string, error) {
	data, err := files.ReadFile("migrations/" + name)
	return string(data), err
}
