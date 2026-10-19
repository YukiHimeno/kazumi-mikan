package main

import (
	"bytes"
	"encoding/base64"
	"testing"

	"github.com/anacrolix/torrent/bencode"
	"github.com/anacrolix/torrent/metainfo"
)

func TestMetainfoSpecPreservesPrivateAndTrackerTiers(t *testing.T) {
	private := true
	infoBytes, err := bencode.Marshal(metainfo.Info{Name: "video.mkv", Length: 10, PieceLength: 16384, Private: &private})
	if err != nil {
		t.Fatal(err)
	}
	mi := metainfo.MetaInfo{InfoBytes: infoBytes, AnnounceList: [][]string{{"https://first/announce", "https://second/announce"}, {"https://third/announce"}}}
	var buf bytes.Buffer
	if err := mi.Write(&buf); err != nil {
		t.Fatal(err)
	}
	spec, err := createSpecFromMetaInfo(base64.StdEncoding.EncodeToString(buf.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(spec.InfoBytes, infoBytes) || spec.InfoHash != mi.HashInfoBytes() {
		t.Fatal("info bytes or hash changed")
	}
	if len(spec.Trackers) != 2 || len(spec.Trackers[0]) != 2 || spec.Trackers[1][0] != "https://third/announce" {
		t.Fatalf("tracker tiers changed: %v", spec.Trackers)
	}
	var parsed metainfo.Info
	if err := bencode.Unmarshal(spec.InfoBytes, &parsed); err != nil || parsed.Private == nil || !*parsed.Private {
		t.Fatalf("private flag lost: %+v %v", parsed, err)
	}
}

func TestInvalidMetainfo(t *testing.T) {
	for _, input := range []string{"not-base64", base64.StdEncoding.EncodeToString([]byte("not bencode"))} {
		if _, err := createSpecFromMetaInfo(input); err == nil {
			t.Fatalf("accepted %q", input)
		}
	}
}
