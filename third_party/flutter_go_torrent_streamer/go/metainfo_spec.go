package main

import (
	"bytes"
	"encoding/base64"
	"errors"
	"fmt"

	"github.com/anacrolix/torrent"
	"github.com/anacrolix/torrent/metainfo"
)

// A metainfo spec carries the original info bytes (including the private flag) and tracker tiers.
func createSpecFromMetaInfo(encoded string) (*torrent.TorrentSpec, error) {
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return nil, fmt.Errorf("invalid torrent base64: %w", err)
	}
	if len(data) == 0 || len(data) > 16*1024*1024 {
		return nil, errors.New("torrent metainfo must be 1 byte to 16 MiB")
	}
	mi, err := metainfo.Load(bytes.NewReader(data))
	if err != nil {
		return nil, fmt.Errorf("invalid torrent metainfo: %w", err)
	}
	spec, err := torrent.TorrentSpecFromMetaInfoErr(mi)
	if err != nil {
		return nil, fmt.Errorf("invalid torrent info: %w", err)
	}
	return spec, nil
}
