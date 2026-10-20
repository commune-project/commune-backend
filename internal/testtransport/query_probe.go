package testtransport

import (
	"context"
	"sync/atomic"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// QueryProbe counts statements on a separate GORM session without modifying
// callbacks or logging SQL/credentials from other tests.
type QueryProbe struct {
	logger.Interface
	count atomic.Int64
	db    *gorm.DB
}

func NewQueryProbe(db *gorm.DB) *QueryProbe {
	p := &QueryProbe{Interface: logger.Discard}
	p.db = db.Session(&gorm.Session{Logger: p})
	return p
}

func (p *QueryProbe) Trace(context.Context, time.Time, func() (string, int64), error) {
	p.count.Add(1)
}

func (p *QueryProbe) DB() *gorm.DB { return p.db }
func (p *QueryProbe) Count() int64 { return p.count.Load() }

// Explain runs the already-bound read query through PostgreSQL's planner.
func Explain(query *gorm.DB) ([]string, error) {
	var lines []string
	err := query.Session(&gorm.Session{NewDB: true}).Raw(
		"EXPLAIN "+query.Statement.SQL.String(), query.Statement.Vars...,
	).Scan(&lines).Error
	return lines, err
}
