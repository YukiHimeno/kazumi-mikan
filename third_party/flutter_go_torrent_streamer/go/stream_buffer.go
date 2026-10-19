package main

import (
	"context"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/anacrolix/torrent"
)

const (
	streamPrebufferBytes = 2 * 1024 * 1024
	streamPrebufferWait  = 5 * time.Second
)

type requestStreamReader struct {
	torrent.Reader
	ctx context.Context
}

func (r requestStreamReader) Read(p []byte) (int, error) {
	return r.Reader.ReadContext(r.ctx, p)
}

func streamRangeOffset(header string, fileLength int64) (int64, bool) {
	if header == "" {
		return 0, fileLength > 0
	}
	if !strings.HasPrefix(header, "bytes=") || strings.Contains(header, ",") {
		return 0, false
	}
	parts := strings.SplitN(strings.TrimPrefix(header, "bytes="), "-", 2)
	if len(parts) != 2 {
		return 0, false
	}
	if parts[0] == "" {
		suffix, err := strconv.ParseInt(parts[1], 10, 64)
		if err != nil || suffix <= 0 || fileLength <= 0 {
			return 0, false
		}
		if suffix > fileLength {
			suffix = fileLength
		}
		return fileLength - suffix, true
	}
	offset, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil || offset < 0 || offset >= fileLength {
		return 0, false
	}
	if parts[1] != "" {
		end, err := strconv.ParseInt(parts[1], 10, 64)
		if err != nil || end < offset {
			return 0, false
		}
	}
	return offset, true
}

func warmStreamReader(r *http.Request, reader torrent.Reader, offset, fileLength int64) {
	if offset < 0 || offset >= fileLength {
		return
	}
	window := int64(streamPrebufferBytes)
	if remaining := fileLength - offset; remaining < window {
		window = remaining
	}
	if _, err := reader.Seek(offset, 0); err != nil {
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), streamPrebufferWait)
	defer cancel()
	buffer := make([]byte, int(window))
	for read := 0; read < len(buffer); {
		n, err := reader.ReadContext(ctx, buffer[read:])
		read += n
		if err != nil || n == 0 {
			break
		}
	}
	_, _ = reader.Seek(offset, 0)
}
