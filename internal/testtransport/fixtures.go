package testtransport

import (
	"database/sql"
	"errors"
	"github.com/DATA-DOG/go-sqlmock"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// Bridge sqlmock's multiple return values into one FFI fixture.
type Fixture struct {
	DB   *sql.DB
	Mock sqlmock.Sqlmock
}

var Failure = errors.New("secret injected failure")

func New() (*Fixture, error) {
	db, mock, err := sqlmock.New(sqlmock.MonitorPingsOption(true))
	if err != nil {
		return nil, err
	}
	return &Fixture{db, mock}, nil
}
func ORM(db *sql.DB) (*gorm.DB, error) {
	return gorm.Open(postgres.New(postgres.Config{Conn: db}), &gorm.Config{DisableAutomaticPing: true, Logger: logger.Discard})
}
func DistinctTransaction(tx, db *gorm.DB) bool {
	return tx != db && tx.Statement.ConnPool != db.Statement.ConnPool
}
func Panics(work func()) (caught bool) {
	defer func() { caught = recover() != nil }()
	work()
	return
}
func Panic() { panic("probe") }
