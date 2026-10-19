package main

import (
	"context"
	"errors"
	"io"
	"net/http/httptest"
	"testing"

	"github.com/anacrolix/torrent"
)

type fakeStreamReader struct {
	data []byte
	pos  int64
}

func (r *fakeStreamReader) Read(p []byte) (int, error) {
	if r.pos >= int64(len(r.data)) {
		return 0, io.EOF
	}
	n := copy(p, r.data[r.pos:])
	r.pos += int64(n)
	return n, nil
}

func (r *fakeStreamReader) ReadContext(ctx context.Context, p []byte) (int, error) {
	select {
	case <-ctx.Done():
		return 0, ctx.Err()
	default:
		return r.Read(p)
	}
}

func (r *fakeStreamReader) Seek(offset int64, whence int) (int64, error) {
	switch whence {
	case io.SeekStart:
		r.pos = offset
	case io.SeekCurrent:
		r.pos += offset
	case io.SeekEnd:
		r.pos = int64(len(r.data)) + offset
	default:
		return r.pos, errors.New("invalid whence")
	}
	return r.pos, nil
}

func (r *fakeStreamReader) Close() error                           { return nil }
func (r *fakeStreamReader) SetReadahead(int64)                     {}
func (r *fakeStreamReader) SetReadaheadFunc(torrent.ReadaheadFunc) {}
func (r *fakeStreamReader) SetResponsive()                         {}

func TestStreamRangeOffset(t *testing.T) {
	cases := []struct {
		header string
		length int64
		want   int64
		ok     bool
	}{
		{"", 100, 0, true},
		{"bytes=12-", 100, 12, true},
		{"bytes=12-20", 100, 12, true},
		{"bytes=-10", 100, 90, true},
		{"bytes=-200", 100, 0, true},
		{"bytes=100-", 100, 0, false},
		{"bytes=10-2", 100, 0, false},
		{"bytes=1-2,5-6", 100, 0, false},
		{"items=1-2", 100, 0, false},
	}
	for _, tc := range cases {
		got, ok := streamRangeOffset(tc.header, tc.length)
		if got != tc.want || ok != tc.ok {
			t.Errorf("streamRangeOffset(%q, %d) = (%d, %v), want (%d, %v)", tc.header, tc.length, got, ok, tc.want, tc.ok)
		}
	}
}

func TestRequestStreamReaderHonorsCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	reader := requestStreamReader{
		Reader: &fakeStreamReader{data: []byte("buffered data")},
		ctx:    ctx,
	}
	buffer := make([]byte, 4)
	if _, err := reader.Read(buffer); err != context.Canceled {
		t.Fatalf("Read error = %v, want context.Canceled", err)
	}
}

func TestWarmStreamReaderRestoresRequestedOffset(t *testing.T) {
	data := make([]byte, streamPrebufferBytes+128)
	reader := &fakeStreamReader{data: data}
	request := httptest.NewRequest("GET", "/stream", nil)
	warmStreamReader(request, reader, 37, int64(len(data)))
	if reader.pos != 37 {
		t.Fatalf("reader position after warmup = %d, want 37", reader.pos)
	}
}
