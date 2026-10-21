package testtransport

import (
	"bufio"
	"fmt"
	"net"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

// FakeSMTP accepts mail only on an ephemeral loopback listener owned by a test.
type FakeSMTP struct {
	Host string
	Port int
	mu sync.Mutex
	messages []string
}

func NewSMTP(t *testing.T) *FakeSMTP {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil { t.Fatal(err) }
	host, port, err := net.SplitHostPort(listener.Addr().String())
	if err != nil { t.Fatal(err) }
	n, err := strconv.Atoi(port)
	if err != nil { t.Fatal(err) }
	s := &FakeSMTP{Host:host, Port:n}
	var workers sync.WaitGroup
	stopped := make(chan struct{})
	go func() {
		defer close(stopped)
		for {
			conn, err := listener.Accept()
			if err != nil { return }
			workers.Add(1)
			go func() {
				defer workers.Done()
				defer conn.Close()
				conn.SetDeadline(time.Now().Add(5*time.Second))
				fmt.Fprint(conn,"220 localhost test SMTP\r\n")
				reader := bufio.NewReader(conn)
				for {
					line, err := reader.ReadString('\n')
					if err != nil { return }
					command := strings.ToUpper(strings.TrimSpace(line))
					switch {
					case command == "DATA":
						fmt.Fprint(conn,"354 send data\r\n")
						var data strings.Builder
						for {
							line, err = reader.ReadString('\n')
							if err != nil { return }
							if line == ".\r\n" { break }
							data.WriteString(line)
						}
						s.mu.Lock(); s.messages=append(s.messages,data.String()); s.mu.Unlock()
						fmt.Fprint(conn,"250 queued\r\n")
					case command == "QUIT":
						fmt.Fprint(conn,"221 bye\r\n"); return
					default:
						fmt.Fprint(conn,"250 localhost\r\n")
					}
				}
			}()
		}
	}()
	t.Cleanup(func(){listener.Close(); <-stopped; workers.Wait()})
	return s
}

func (s *FakeSMTP) Messages() []string {
	s.mu.Lock(); defer s.mu.Unlock()
	return append([]string(nil),s.messages...)
}
